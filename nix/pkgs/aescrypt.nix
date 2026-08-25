{
  writeShellApplication,
  openssl,
  coreutils,
}:

writeShellApplication {
  name = "aescrypt";
  runtimeInputs = [
    openssl
    coreutils
  ];
  text = builtins.readFile ../../.local/bin/aescrypt.sh;
}
