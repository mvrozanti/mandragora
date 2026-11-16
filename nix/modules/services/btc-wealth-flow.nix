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
  publicPort = 8420;
  processorPort = 18420;
  supervisor = import ../../pkgs/idle-socket-supervisor.nix { inherit pkgs; };
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
    "--listen"
    "127.0.0.1:${toString processorPort}"
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
    port = publicPort;
    userService = true;
    memoryMax = "8G";
    systemd = {
      description = "btc-wealth-flow server for btc.mvr.ac on :${toString publicPort}: woken by its socket on the first visit, serves the aggregates, on request starts the scan node and ingests up to the chain tip, and stops after 15 idle minutes unless the scan node is running";
      requires = [ "btc-flow-processor.socket" ];
      after = [ "btc-flow-processor.socket" ];
      path = [ config.systemd.package ];
      environment = {
        UPSTREAM_ADDR = "127.0.0.1";
        UPSTREAM_PORT = toString processorPort;
        IDLE_TIMEOUT = "900";
        STARTUP_TIMEOUT = "60";
        BUSY_CHECK = "${config.systemd.package}/bin/systemctl --user is-active --quiet btc-flow-scan.service";
      };
      serviceConfig = {
        ExecStart = "${supervisor}/bin/idle-socket-supervisor ${
          execLine ([ "${repo}/result/bin/btc-wealth-flow" ] ++ processorArgs)
        }";
        Restart = "on-failure";
        RestartSec = "1s";
        MemoryHigh = "6G";
        MemorySwapMax = "0";
        CPUWeight = 20;
      };
    };
  };

  systemd.user.sockets.btc-flow-processor = {
    description = "btc-wealth-flow socket: holds :${toString publicPort} while the server is stopped";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "0.0.0.0:${toString publicPort}" ];
    unitConfig.ConditionUser = "m";
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
