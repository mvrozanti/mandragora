{
  config,
  lib,
  pkgs,
  ...
}:

let
  repo = "/home/m/Projects/btc-wealth-flow";
  data = "/home/m/.local/share/btc-wealth-flow";
  rpcUser = "m";
  rpcPort = 18443;
  rpcAuth = "${rpcUser}:${config.services.bitcoind.main.rpc.users.${rpcUser}.passwordHMAC}";
  execLine = argv: lib.replaceStrings [ "$" ] [ "$$" ] (lib.escapeShellArgs argv);
  scanArgs = [
    "-datadir=${data}/scan"
    "-port=18444"
    "-rpcport=${toString rpcPort}"
    "-rpcbind=127.0.0.1"
    "-rpcallowip=127.0.0.1"
    "-rpcauth=${rpcAuth}"
    "-prune=250000"
    "-par=6"
    "-server"
    "-dbcache=2000"
    "-blocksonly=1"
    "-printtoconsole=0"
    "-disablewallet"
  ];
  processorArgs = [
    "--sqlite"
    "${data}/utxo.sqlite"
    "--duck"
    "${data}/flow.duckdb"
    "--rpc-url"
    "http://127.0.0.1:${toString rpcPort}"
    "--rpc-user"
    rpcUser
    "--rpc-pass-file"
    config.sops.secrets."bitcoin/rpc_password".path
  ];
in
{
  systemd.user.services.btc-flow-scan = {
    description = "btc-wealth-flow scan node: pruned bitcoind the ingest reads blocks from and prunes behind its commits";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "m";
    serviceConfig = {
      ExecStart = execLine ([ "${pkgs.bitcoind}/bin/bitcoind" ] ++ scanArgs);
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStopSec = "10min";
      MemoryHigh = "4G";
      MemoryMax = "5G";
      MemorySwapMax = "0";
      CPUWeight = 20;
      IOWeight = 10;
    };
  };

  mandragora.hub.services.btc-flow-processor = {
    port = 8420;
    userService = true;
    memoryMax = "8G";
    systemd = {
      description = "btc-wealth-flow ingest and server for btc.mvr.ac: turns scan-node blocks into aggregates, prunes the scan node behind its commits, serves :8420";
      after = [ "btc-flow-scan.service" ];
      wants = [ "btc-flow-scan.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = execLine ([ "${repo}/result/bin/btc-wealth-flow" ] ++ processorArgs);
        Restart = "on-failure";
        RestartSec = "5s";
        MemoryHigh = "6G";
        MemorySwapMax = "0";
        CPUWeight = 20;
        IOWeight = 10;
      };
    };
  };

  systemd.user.services.btc-flow-pause = {
    description = "btc-wealth-flow pause coordinator: stops the scan node's download while it runs more than 1000 blocks ahead of the ingest";
    after = [
      "btc-flow-scan.service"
      "btc-flow-processor.service"
    ];
    wants = [ "btc-flow-scan.service" ];
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "m";
    path = [
      pkgs.curl
      pkgs.python3
      pkgs.coreutils
    ];
    serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash ${repo}/pause-coordinator.sh";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
