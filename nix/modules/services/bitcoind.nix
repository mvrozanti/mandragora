{ config, pkgs, ... }:

let
  rpcUser = "m";
  rpcPasswordHMAC = "b18e46fb5dc3569e007eb1d91d4d457a$7675ed852f946c3a000d36c6434c559f2fb588814dd1959302e96d65cbaa19e9";
  bitcoinCli = pkgs.writeShellScriptBin "bitcoin-cli-m" ''
    exec ${pkgs.bitcoind}/bin/bitcoin-cli \
      -rpcconnect=127.0.0.1 \
      -rpcport=8332 \
      -rpcuser=${rpcUser} \
      -stdinrpcpass \
      "$@" < ${config.sops.secrets."bitcoin/rpc_password".path}
  '';
in
{
  services.bitcoind.main = {
    enable = false;
    dataDir = "/persistent/bitcoin";
    prune = 550;
    dbCache = 4000;
    rpc.users.${rpcUser}.passwordHMAC = rpcPasswordHMAC;
    extraCmdlineOptions = [
      "-server"
      "-par=8"
    ];
  };

  environment.systemPackages = [ bitcoinCli ];
}
