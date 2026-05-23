{ pkgs }:

let
  runtimeLibs = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    glibc
    libxml2
    libxslt
    sqlite
    icu
    openssl
    curl
    libffi
    bzip2
    xz
    zstd

    xorg.libX11
    xorg.libXcursor
    xorg.libXrandr
    xorg.libXinerama
    xorg.libXi
    xorg.libXScrnSaver
    xorg.libXrender
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXtst
    xorg.libxcb
    xorg.libxshmfence
    xorg.xcbutilimage
    xorg.xcbutilkeysyms
    xorg.xcbutilwm
    xorg.libICE
    xorg.libSM

    wayland
    libxkbcommon

    libGL
    mesa
    libgbm
    vulkan-loader
    vulkan-tools
    vulkan-validation-layers
    libdrm

    alsa-lib
    libpulseaudio

    fontconfig
    freetype
    harfbuzz
    dbus
    glib
    gtk3
    cairo
    pango
    gdk-pixbuf
    atk
    at-spi2-core
    at-spi2-atk

    nss
    nspr
    cups
    expat

    libuuid
    libusb1
    libsecret
    libnotify
    systemd
  ];

  buildTools = with pkgs; [
    clang_18
    lld_18
    llvm_18
    gnumake
    cmake
    ninja
    pkg-config
    python3
    dotnet-sdk_8
    mono
    git
    git-lfs
    unzip
    wget
    curl
    which
    binutils
    patchelf
    file
  ];

  fhs = pkgs.buildFHSEnv {
    name = "ue5-fhs";
    targetPkgs = _: buildTools ++ runtimeLibs;
    multiPkgs = _: runtimeLibs;
    profile = ''
      export UE_ROOT="''${UE_ROOT:-/persistent/etc/UnrealEngine}"
      export PROJECT_ROOT="''${PROJECT_ROOT:-$PWD}"
      export DOTNET_ROOT="${pkgs.dotnet-sdk_8}/share/dotnet"
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver-32/lib:''${LD_LIBRARY_PATH:-}"
      export VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json"
      export __GL_THREADED_OPTIMIZATIONS=1
      export QT_QPA_PLATFORM=wayland
      export GDK_BACKEND=wayland
      export SDL_VIDEODRIVER=wayland
    '';
    runScript = "bash";
  };

  discoverUproject = ''
    if [ -z "''${UPROJECT:-}" ]; then
      shopt -s nullglob
      candidates=("''${PROJECT_ROOT:?PROJECT_ROOT not set}"/*.uproject)
      shopt -u nullglob
      if [ ''${#candidates[@]} -eq 0 ]; then
        echo "error: no *.uproject in $PROJECT_ROOT (set UPROJECT to override)" >&2
        exit 1
      fi
      UPROJECT="''${candidates[0]}"
    fi
  '';

  discoverTarget = ''
    if [ -z "''${UE_TARGET:-}" ]; then
      base="$(basename "$UPROJECT" .uproject)"
      UE_TARGET="''${base}Editor"
    fi
  '';

  mkScript = name: body: pkgs.writeShellScriptBin name body;

  ue5-setup = mkScript "ue5-setup" ''
    set -euo pipefail
    cd "''${UE_ROOT:?UE_ROOT not set}"
    echo "Running Setup.sh in $UE_ROOT"
    ./Setup.sh
    echo "Generating engine project files"
    ./GenerateProjectFiles.sh
  '';

  ue5-build-engine = mkScript "ue5-build-engine" ''
    set -euo pipefail
    cd "''${UE_ROOT:?UE_ROOT not set}"
    make -j"$(nproc)" UnrealEditor
  '';

  ue5-generate = mkScript "ue5-generate" ''
    set -euo pipefail
    export PROJECT_ROOT="''${PROJECT_ROOT:-$PWD}"
    ${discoverUproject}
    "''${UE_ROOT:?UE_ROOT not set}/GenerateProjectFiles.sh" -project="$UPROJECT" -game -engine
  '';

  ue5-build = mkScript "ue5-build" ''
    set -euo pipefail
    export PROJECT_ROOT="''${PROJECT_ROOT:-$PWD}"
    ${discoverUproject}
    ${discoverTarget}
    "''${UE_ROOT:?UE_ROOT not set}/Engine/Build/BatchFiles/Linux/Build.sh" \
      "$UE_TARGET" Linux Development "$UPROJECT" -waitmutex
  '';

  ue5-editor = mkScript "ue5-editor" ''
    set -euo pipefail
    export PROJECT_ROOT="''${PROJECT_ROOT:-$PWD}"
    ${discoverUproject}
    exec "''${UE_ROOT:?UE_ROOT not set}/Engine/Binaries/Linux/UnrealEditor" "$UPROJECT" "$@"
  '';

  scripts = [ ue5-setup ue5-build-engine ue5-generate ue5-build ue5-editor ];

  devShell = pkgs.mkShell {
    packages = [ fhs ] ++ scripts;
    shellHook = ''
      export UE_ROOT="''${UE_ROOT:-/persistent/etc/UnrealEngine}"
      export PROJECT_ROOT="''${PROJECT_ROOT:-$PWD}"
      echo "==[ Mandragora UE5 devShell ]=="
      echo "  UE_ROOT      = $UE_ROOT"
      echo "  PROJECT_ROOT = $PROJECT_ROOT"
      echo
      echo "Commands (run inside 'ue5-fhs'):"
      echo "  ue5-fhs                 # FHS shell with all UE5 libs"
      echo "  ue5-setup               # UE Setup.sh + GenerateProjectFiles.sh"
      echo "  ue5-build-engine        # build UnrealEditor (one-time, ~1h)"
      echo "  ue5-generate            # regenerate project files for current *.uproject"
      echo "  ue5-build               # build <Project>Editor target"
      echo "  ue5-editor              # launch editor on current project"
      if [ ! -d "$UE_ROOT" ]; then
        echo
        echo "WARNING: UE_ROOT=$UE_ROOT does not exist."
        echo "  Clone UnrealEngine source there (requires Epic+GitHub link)."
      fi
    '';
  };
in
{
  inherit fhs scripts devShell;
  inherit ue5-setup ue5-build-engine ue5-generate ue5-build ue5-editor;
}
