{ lib, pkgs, ... }:

let
  exprs = import ../core/monitoring-exprs.nix;
  hub = builtins.fromJSON (
    builtins.readFile ../../hosts/mandragora-vps/compose/hub/static/services.json
  );
  desk = exprs {
    instance = "mandragora-desktop";
    disk = "nvme0n1";
    nic = "enp8s0";
  };
  vps = exprs {
    instance = "mandragora-vps";
    disk = "sda";
    nic = "eth0";
  };

  series = key: label: unit: expr: warn: crit: {
    inherit
      key
      label
      unit
      expr
      warn
      crit
      ;
  };
  card = s: s // { card = true; };
  fact = key: label: unit: expr: {
    inherit
      key
      label
      unit
      expr
      ;
  };

  spec = {
    period = 60;
    step = 300;
    window = 86400;
    hosts = {
      desk = {
        label = "mandragora";
        series = [
          (card (series "cpu" "cpu" "%" desk.cpuBusy 50 85))
          (card (series "mem" "memory" "%" desk.memUsed 85 94))
          (card (series "gpu" "gpu" "%" desk.gpuUtil 50 85))
          (card (series "vram" "vram" "%" desk.gpuMem 60 90))
          (card (series "gputemp" "gpu temp" "°C" desk.gpuTemp 60 78))
          (series "gpupower" "gpu power" "W" desk.gpuPower null null)
          (series "disk" "nvme0n1 busy" "%" desk.diskUtil 75 92)
          (series "psi_cpu" "cpu stall" "%" desk.psiCpu 12 25)
          (series "psi_mem" "memory stall" "%" desk.psiMem 20 40)
          (series "psi_io" "io stall" "%" desk.psiIo 30 50)
          (series "load" "load per core" "%" desk.loadPc 120 200)
          (series "rx" "net in" "B/s" desk.rx null null)
          (series "tx" "net out" "B/s" desk.tx null null)
        ];
        facts = [
          (fact "uptime" "uptime" "s" desk.uptime)
          (fact "memTotal" "memory" "GiB" desk.memTotal)
          (fact "swapUsed" "swap used" "GiB" desk.swapUsed)
          (fact "rxToday" "in, 24 h" "B" desk.rxToday)
          (fact "txToday" "out, 24 h" "B" desk.txToday)
        ];
      };
      vps = {
        label = "mandragora-vps";
        series = [
          (card (series "cpu" "cpu" "%" vps.cpuBusy 50 85))
          (series "iowait" "iowait" "%" vps.iowait 10 25)
          (card (series "mem" "memory" "%" vps.memUsed 85 94))
          (series "disk" "sda busy" "%" vps.diskUtil 75 92)
          (series "load" "load per core" "%" vps.loadPc 120 200)
          (series "rx" "net in" "B/s" vps.rx null null)
          (series "tx" "net out" "B/s" vps.tx null null)
        ];
        facts = [
          (fact "uptime" "uptime" "s" vps.uptime)
          (fact "memTotal" "memory" "GiB" vps.memTotal)
          (fact "rxToday" "in, 24 h" "B" vps.rxToday)
          (fact "txToday" "out, 24 h" "B" vps.txToday)
        ];
      };
    };
    probes = {
      job = "blackbox-subdomains";
      sample = 60;
      slowMs = hub.probe.slow_ms;
      gateCodes = hub.probe.gate_codes;
      hosts = map (svc: svc.host) hub.services;
    };
  };

  privateMarkers = [
    "namedprocess_"
    "ebpf_exporter_cgroup"
    "dirsize_"
    "dir_inode"
    "topk("
    " by ("
    " without ("
  ];
  publicExprs = lib.concatMap (h: map (x: x.expr) (h.series ++ h.facts)) (lib.attrValues spec.hosts);
  leaks = lib.filter (e: lib.any (m: lib.hasInfix m e) privateMarkers) publicExprs;

  specFile = pkgs.writeText "status-snapshot-spec.json" (builtins.toJSON spec);
  src = ../../../.local/share/status-snapshot/status_snapshot.py;
  outDir = "/run/status-snapshot";
in
{
  assertions = [
    {
      assertion = leaks == [ ];
      message = "status-snapshot: the public set may only carry label-free host series; offending: ${lib.concatStringsSep " | " leaks}";
    }
  ];

  systemd.services.status-snapshot = {
    description = "status-snapshot — curated public metrics for status.mvr.ac";
    after = [ "victoriametrics.service" ];
    wants = [ "victoriametrics.service" ];
    environment.VM_URL = "http://127.0.0.1:8428";
    serviceConfig = {
      Type = "oneshot";
      User = "m";
      Group = "users";
      RuntimeDirectory = "status-snapshot";
      RuntimeDirectoryPreserve = "yes";
      ExecStart = "${pkgs.python3}/bin/python3 ${src} ${specFile} ${outDir}/status.json";
      MemoryMax = "128M";
      TimeoutStartSec = "45s";
    };
  };

  systemd.timers.status-snapshot = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "45s";
      OnUnitActiveSec = "${toString spec.period}s";
      AccuracySec = "5s";
    };
  };

}
