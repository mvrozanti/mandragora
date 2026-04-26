{ pkgs, usbImage }:

let
  ovmf = pkgs.OVMF.fd;
  scripts = pkgs.runCommand "refiner-scripts" { } ''
    mkdir -p $out
    cp ${./run-vm.sh} $out/run-vm.sh
    cp ${./lib.sh} $out/lib.sh
    chmod +x $out/run-vm.sh
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
  ];
  text = ''
    export MANDRAGORA_USB_IMG="${usbImage}/nixos.img"
    export MANDRAGORA_OVMF_CODE="${ovmf}/FV/OVMF_CODE.fd"
    export MANDRAGORA_OVMF_VARS="${ovmf}/FV/OVMF_VARS.fd"
    exec ${scripts}/run-vm.sh "$@"
  '';
}
