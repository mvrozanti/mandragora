{ stdenvNoCC, clang, libbpf, prometheus-ebpf-exporter }:
stdenvNoCC.mkDerivation {
  pname = "ebpf-network-config";
  version = "0.1.0";

  srcs = [
    ./network-cgroup.bpf.c
    ./network-cgroup.yaml
  ];

  unpackPhase = ''
    for f in $srcs; do
      cp "$f" "$(stripHash "$f")"
    done
    cp ${prometheus-ebpf-exporter.src}/examples/maps.bpf.h .
    cp ${prometheus-ebpf-exporter.src}/examples/bits.bpf.h .
    cp ${prometheus-ebpf-exporter.src}/include/x86/vmlinux.h .
  '';

  buildInputs = [ libbpf ];

  buildPhase = ''
    CLANG=${clang.cc}/bin/clang
    SYS_INCLUDES=$($CLANG -v -E - </dev/null 2>&1 \
      | sed -n '/<...> search starts here:/,/End of search list./{ s| \(/.*\)|-idirafter \1|p }')
    $CLANG \
      -mcpu=v3 -g -O2 -D__TARGET_ARCH_x86 \
      $SYS_INCLUDES \
      -I${libbpf}/include \
      -I. \
      -c -target bpf network-cgroup.bpf.c \
      -o network-cgroup.bpf.o
  '';

  installPhase = ''
    mkdir -p $out
    cp network-cgroup.bpf.o network-cgroup.yaml $out/
  '';

  meta = {
    description = "ebpf_exporter config for per-cgroup TCP byte counters";
    platforms = [ "x86_64-linux" ];
  };
}
