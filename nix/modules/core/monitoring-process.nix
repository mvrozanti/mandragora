_:

{
  services.prometheus.exporters.process = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9256;
    extraFlags = [ "-threads=false" ];
    settings.process_names = [
      {
        name = "claude-deepseek";
        cmdline = [ "cc-pocket-bridge" ];
      }
      {
        name = "claude-web";
        cmdline = [ "claude-web/app\\.py" ];
      }
      {
        name = "autoclaude";
        cmdline = [ "/autoclaude\\b" ];
      }
      {
        name = "claude";
        cmdline = [ "claude-code-[0-9.]+/lib/claude-code/claude" ];
      }
      {
        name = "firefox";
        cmdline = [
          "firefox-[0-9.]+/lib/firefox/firefox"
          "/bin/firefox$"
        ];
      }
      {
        name = "kitty";
        cmdline = [
          "kitty-[0-9.]+/bin/kitt(y|en)"
          "/bin/kitty\\b"
        ];
      }
      {
        name = "hyprland";
        cmdline = [ "/bin/Hyprland\\b" ];
      }
      {
        name = "im-gen-bot";
        cmdline = [ "im-gen/.*\\bbot\\.py" ];
      }
      {
        name = "im-gen-webui";
        cmdline = [ "im-gen/webui/app\\.py" ];
      }
      {
        name = "ea-desktop";
        cmdline = [
          "EADesktop\\.exe"
          "EACefSubProcess\\.exe"
        ];
      }
      {
        name = "wine";
        cmdline = [ "\\.exe\\b" ];
      }
      {
        name = "{{.Matches.Script}}";
        cmdline = [ "python[0-9.]*\\s+(?:-[^\\s]+\\s+)*[^\\s]*/(?P<Script>[A-Za-z0-9_.-]+\\.py)\\b" ];
      }
      {
        name = "{{.Matches.Script}}";
        cmdline = [ "python[0-9.]*\\s+(?P<Script>[A-Za-z0-9_.-]+\\.py)\\b" ];
      }
      {
        name = "{{.Matches.Bin}}";
        cmdline = [ "^/nix/store/[a-z0-9]+-[^/]+/bin/(?P<Bin>[A-Za-z0-9_.-]+)" ];
      }
      {
        name = "{{.Matches.Bin}}";
        cmdline = [
          "^/nix/store/[a-z0-9]+-[^/]+/(?:lib|libexec)/[^\\s]*?(?P<Bin>[A-Za-z0-9_.-]+)(?:\\s|$)"
        ];
      }
      {
        name = "{{.ExeBase}}";
        cmdline = [ "." ];
      }
    ];
  };
}
