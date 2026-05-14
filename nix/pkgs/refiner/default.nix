{ pkgs, usbImage }:

let
  ovmf = pkgs.OVMF.fd;
  scripts = pkgs.runCommand "refiner-scripts" { } ''
    mkdir -p $out
    cp ${./run-vm.sh}       $out/run-vm.sh
    cp ${./lib.sh}          $out/lib.sh
    cp ${./auto-install.sh} $out/auto-install.sh
    chmod +x $out/run-vm.sh $out/auto-install.sh
  '';
in
pkgs.writeShellApplication {
  name = "refiner";
  runtimeInputs = with pkgs; [
    qemu_kvm
    coreutils
    util-linux
    e2fsprogs
    dosfstools
    gawk
    sshpass
    openssh
    netcat-gnu
  ];
  text = ''
    export MANDRAGORA_USB_IMG="${usbImage}/nixos.img"
    export MANDRAGORA_OVMF_CODE="${ovmf}/FV/OVMF_CODE.fd"
    export MANDRAGORA_OVMF_VARS="${ovmf}/FV/OVMF_VARS.fd"
    if [[ "''${1:-}" == "--auto" ]]; then
        shift
        exec ${scripts}/auto-install.sh "$@"
    fi
    exec ${scripts}/run-vm.sh "$@"
  '';
}
