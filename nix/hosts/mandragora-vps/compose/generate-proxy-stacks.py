#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "proxy-stacks.json"
TAILNET = HERE / "../../../snippets/tailnet.json"

FORWARD_AUTH = [
    'forward_auth: "authelia:9091"',
    'forward_auth.uri: "/api/authz/forward-auth"',
    'forward_auth.copy_headers: "Remote-User Remote-Groups Remote-Name Remote-Email"',
]

LOGGING_BLOCK = [
    "    logging:",
    "      driver: json-file",
    "      options:",
    '        max-size: "10m"',
    '        max-file: "3"',
]

NETWORKS_BLOCK = [
    "networks:",
    "  seafile-net:",
    "    external: true",
]


def resolve_ip(tailnet, host_key):
    node = tailnet.get(host_key)
    if node is None or "ip" not in node:
        raise KeyError(f"tailnet.json has no ip for host key '{host_key}'")
    return node["ip"]


def upstream_default(tailnet, host_key, port):
    return f"{resolve_ip(tailnet, host_key)}:{port}"


def labels_authelia_simple(stack, tailnet):
    host = stack["host"]
    upstream = upstream_default(tailnet, stack["upstream_host"], stack["upstream_port"])
    lines = [
        "    labels:",
        f"      caddy: https://{host}.${{MVR_AC:-mvr.ac}}",
    ]
    lines += [f"      caddy.0_handle.{tail}" for tail in FORWARD_AUTH]
    if "request_body_max_size" in stack:
        lines.append(
            f'      caddy.0_handle.request_body.max_size: "{stack["request_body_max_size"]}"'
        )
    lines += [
        f'      caddy.0_handle.reverse_proxy: "${{{stack["upstream_var"]}:-{upstream}}}"',
        '      caddy.0_handle.reverse_proxy.flush_interval: "-1"',
        '      caddy.0_handle.reverse_proxy.transport: "http"',
    ]
    return lines


def labels_authelia_split(stack, tailnet):
    host = stack["host"]
    api = upstream_default(tailnet, stack["api_upstream_host"], stack["api_upstream_port"])
    web = upstream_default(tailnet, stack["web_upstream_host"], stack["web_upstream_port"])
    lines = [
        "    labels:",
        f"      caddy: https://{host}.${{MVR_AC:-mvr.ac}}",
        '      caddy.0_handle_path: "/api/*"',
    ]
    lines += [f"      caddy.0_handle_path.{tail}" for tail in FORWARD_AUTH]
    lines += [
        f'      caddy.0_handle_path.reverse_proxy: "${{{stack["api_upstream_var"]}:-{api}}}"',
        '      caddy.0_handle_path.reverse_proxy.flush_interval: "-1"',
        '      caddy.0_handle_path.reverse_proxy.transport: "http"',
    ]
    lines += [f"      caddy.1_handle.{tail}" for tail in FORWARD_AUTH]
    lines += [
        f'      caddy.1_handle.reverse_proxy: "${{{stack["web_upstream_var"]}:-{web}}}"',
        '      caddy.1_handle.reverse_proxy.transport: "http"',
    ]
    return lines


def labels_basic_auth(stack, tailnet):
    host = stack["host"]
    upstream = upstream_default(tailnet, stack["upstream_host"], stack["upstream_port"])
    return [
        "    labels:",
        f"      caddy: https://{host}.${{MVR_AC:-mvr.ac}}",
        "      caddy.encode: zstd gzip",
        f'      caddy.basic_auth.{stack["basic_auth_user"]}: "${{{stack["basic_auth_var"]}}}"',
        f'      caddy.reverse_proxy: "${{{stack["upstream_var"]}:-{upstream}}}"',
        '      caddy.reverse_proxy.flush_interval: "-1"',
        '      caddy.reverse_proxy.transport: "http"',
    ]


LABEL_BUILDERS = {
    "authelia-simple": labels_authelia_simple,
    "authelia-split": labels_authelia_split,
    "basic-auth": labels_basic_auth,
}


def render(stack, tailnet):
    kind = stack["kind"]
    builder = LABEL_BUILDERS.get(kind)
    if builder is None:
        raise ValueError(f"unknown kind '{kind}' for stack '{stack['name']}'")
    service = f"{stack['name']}-proxy"
    lines = ["services:", ""]
    for comment in stack.get("comment", []):
        lines.append(f"  # {comment.format(desktop=resolve_ip(tailnet, 'desktop'))}")
    lines += [
        f"  {service}:",
        "    image: alpine:3.20",
        f"    container_name: {service}",
        "    restart: unless-stopped",
        '    command: ["sh", "-c", "while true; do sleep 3600; done"]',
        "    networks:",
        "      - seafile-net",
    ]
    lines += builder(stack, tailnet)
    if stack.get("logging", False):
        lines += LOGGING_BLOCK
    lines.append("")
    lines += NETWORKS_BLOCK
    return "\n".join(lines) + "\n"


def load():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    tailnet = json.loads(TAILNET.read_text(encoding="utf-8"))
    return manifest["stacks"], tailnet


def main():
    parser = argparse.ArgumentParser(
        description="Generate the label-only reverse-proxy shim compose files from proxy-stacks.json."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify on-disk files match the generator output; exit 1 on drift.",
    )
    args = parser.parse_args()

    stacks, tailnet = load()
    drift = []
    for stack in stacks:
        target = HERE / stack["name"] / "docker-compose.yml"
        rendered = render(stack, tailnet)
        if args.check:
            current = target.read_text(encoding="utf-8") if target.exists() else ""
            if current != rendered:
                drift.append(stack["name"])
        else:
            target.write_text(rendered, encoding="utf-8")

    if args.check:
        if drift:
            print(
                "proxy-stacks drift in: " + ", ".join(drift) + "\nrun the generator: "
                "nix/hosts/mandragora-vps/compose/generate-proxy-stacks.py",
                file=sys.stderr,
            )
            return 1
        print("proxy-stacks: all generated compose files match the manifest")
    else:
        print(f"proxy-stacks: wrote {len(stacks)} compose files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
