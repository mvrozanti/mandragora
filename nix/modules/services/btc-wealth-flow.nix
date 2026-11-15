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
    "--node-unit"
    "btc-flow-scan.service"
  ];
in
{
  systemd.user.services.btc-flow-scan = {
    description = "btc-wealth-flow scan node: pruned bitcoind an update reads blocks from, started and stopped from btc.mvr.ac";
    wants = [ "btc-flow-pause.service" ];
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
    };
  };

  mandragora.hub.services.btc-flow-processor = {
    port = 8420;
    userService = true;
    memoryMax = "8G";
    systemd = {
      description = "btc-wealth-flow server for btc.mvr.ac on :8420: serves the aggregates, and on request starts the scan node and ingests up to the chain tip";
      wantedBy = [ "default.target" ];
      path = [ config.systemd.package ];
      serviceConfig = {
        ExecStart = execLine ([ "${repo}/result/bin/btc-wealth-flow" ] ++ processorArgs);
        Restart = "always";
        RestartSec = "1s";
        MemoryHigh = "6G";
        MemorySwapMax = "0";
        CPUWeight = 20;
      };
    };
  };

  systemd.user.services.btc-flow-pause = {
    description = "btc-wealth-flow pause coordinator: stops the scan node's download while it runs more than 1000 blocks ahead of the ingest";
    after = [ "btc-flow-scan.service" ];
    bindsTo = [ "btc-flow-scan.service" ];
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
