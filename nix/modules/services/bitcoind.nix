{ config, pkgs, ... }:

let
  rpcUser = "m";
  rpcPasswordHMAC = "1bbd4992a3070619550ab6f640155db9$f2e79d9d97ff4e8e61469e26d1716db1eda5eefffad94f89c636ce5cc0719250";
  bitcoinCli = pkgs.writeShellScriptBin "bitcoin-cli-m" ''
    exec ${pkgs.bitcoind}/bin/bitcoin-cli \
      -datadir=/persistent/bitcoin \
      -rpcuser=${rpcUser} \
      -stdinrpcpass \
      "$@" < ${config.sops.secrets."bitcoin/rpc_password".path}
  '';
in
{
  services.bitcoind.main = {
    enable = true;
    dataDir = "/persistent/bitcoin";
    prune = 550;
    dbCache = 4000;
    rpc.users.${rpcUser}.passwordHMAC = rpcPasswordHMAC;
    extraCmdlineOptions = [ "-server" ];
  };

  users.users.m.extraGroups = [ "bitcoind-main" ];

  environment.systemPackages = [ bitcoinCli ];

  systemd.services.bitcoind-main = {
    requires = [ "persistent.mount" ];
    after = [ "persistent.mount" ];
  };
}
