_:

{
  nixpkgs.overlays = [
    (_final: prev: {
      openldap = prev.openldap.overrideAttrs (_oldAttrs: {
        doCheck = false;
      });

      yt-dlp = prev.yt-dlp.overridePythonAttrs (_oldAttrs: rec {
        version = "2026.08.19";
        src = prev.fetchFromGitHub {
          owner = "yt-dlp";
          repo = "yt-dlp";
          tag = version;
          hash = "sha256-BM5ZeGTmHq+1xH6G/zsuCtjLgYgfRA11ya0zIHK5p4g=";
        };
      });
    })
  ];
}
