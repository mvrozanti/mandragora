{
  config,
  pkgs,
  lib,
  ...
}:

let
  tailnet = builtins.fromJSON (builtins.readFile ../../snippets/tailnet.json);
  mkSystemDashboard =
    {
      title,
      uid,
      instance,
      nic,
      disk,
      refresh ? "30s",
      withGpu ? false,
      withEbpf ? false,
      withDirsize ? false,
      withFsUsage ? false,
      withPressure ? false,
      withProcs ? false,
    }:
    let
      inst = ''instance="${instance}"'';
      ds = {
        type = "prometheus";
        uid = "prometheus";
      };
      mkT = i: expr: legend: {
        datasource = ds;
        inherit expr;
        legendFormat = legend;
        refId = builtins.substring i 1 "ABCDEF";
      };
      st = color: value: { inherit color value; };
      neutral = [ (st "text" null) ];
      psiIo = [
        (st "green" null)
        (st "#EAB839" 15)
        (st "orange" 30)
        (st "red" 50)
      ];
      psiMem = [
        (st "green" null)
        (st "#EAB839" 8)
        (st "orange" 20)
        (st "red" 40)
      ];
      psiCpu = [
        (st "green" null)
        (st "#EAB839" 5)
        (st "orange" 12)
        (st "red" 25)
      ];
      loadPc = [
        (st "green" null)
        (st "#EAB839" 80)
        (st "orange" 120)
        (st "red" 200)
      ];
      swapRate = [
        (st "green" null)
        (st "#EAB839" 200)
        (st "orange" 1500)
        (st "red" 6000)
      ];
      blocked = [
        (st "green" null)
        (st "#EAB839" 1)
        (st "orange" 4)
        (st "red" 12)
      ];
      diskUtil = [
        (st "green" null)
        (st "#EAB839" 50)
        (st "orange" 75)
        (st "red" 92)
      ];
      memUsed = [
        (st "green" null)
        (st "#EAB839" 70)
        (st "orange" 85)
        (st "red" 94)
      ];
      memFree = [
        (st "red" null)
        (st "orange" 2)
        (st "#EAB839" 5)
        (st "green" 10)
      ];
      pos = x: y: w: h: {
        inherit
          x
          y
          w
          h
          ;
      };
      mkRow = id: rowTitle: y: {
        inherit id;
        title = rowTitle;
        type = "row";
        collapsed = false;
        panels = [ ];
        gridPos = pos 0 y 24 1;
      };
      mkGauge =
        {
          id,
          title,
          expr,
          gridPos,
          unit ? "percent",
          max ? 100,
          steps ? neutral,
        }:
        {
          inherit id title gridPos;
          type = "gauge";
          datasource = ds;
          targets = [ (mkT 0 expr "") ];
          fieldConfig = {
            defaults = {
              inherit unit max;
              min = 0;
              color.mode = "thresholds";
              thresholds = {
                mode = "absolute";
                inherit steps;
              };
            };
            overrides = [ ];
          };
          options = {
            showThresholdLabels = false;
            showThresholdMarkers = true;
            reduceOptions = {
              calcs = [ "lastNotNull" ];
              fields = "";
              values = false;
            };
          };
        };
      mkStat =
        {
          id,
          title,
          expr,
          gridPos,
          unit ? "percent",
          decimals ? 1,
          steps ? neutral,
          graphMode ? "area",
        }:
        {
          inherit id title gridPos;
          type = "stat";
          datasource = ds;
          targets = [ (mkT 0 expr "") ];
          fieldConfig = {
            defaults = {
              inherit unit decimals;
              color.mode = "thresholds";
              thresholds = {
                mode = "absolute";
                inherit steps;
              };
            };
            overrides = [ ];
          };
          options = {
            inherit graphMode;
            colorMode = "value";
            justifyMode = "auto";
            textMode = "auto";
            reduceOptions = {
              calcs = [ "lastNotNull" ];
              fields = "";
              values = false;
            };
          };
        };
      mkTs =
        {
          id,
          title,
          targets,
          gridPos,
          unit ? "percent",
          steps ? neutral,
          fillOpacity ? 16,
          description ? null,
        }:
        {
          inherit
            id
            title
            gridPos
            targets
            ;
          type = "timeseries";
          datasource = ds;
          fieldConfig = {
            defaults = {
              inherit unit;
              color.mode = if steps == neutral then "palette-classic" else "thresholds";
              custom = {
                inherit fillOpacity;
                gradientMode = "opacity";
                lineWidth = 1;
                showPoints = "never";
                spanNulls = true;
              };
              thresholds = {
                mode = "absolute";
                inherit steps;
              };
            };
            overrides = [ ];
          };
          options = {
            legend = {
              displayMode = "list";
              placement = "bottom";
              showLegend = true;
            };
            tooltip = {
              mode = "multi";
              sort = "desc";
            };
          };
        }
        // lib.optionalAttrs (description != null) { inherit description; };
      mkBar =
        {
          id,
          title,
          expr,
          legend,
          gridPos,
          unit,
          steps ? neutral,
        }:
        {
          inherit id title gridPos;
          type = "bargauge";
          datasource = ds;
          targets = [ (mkT 0 expr legend) ];
          fieldConfig = {
            defaults = {
              inherit unit;
              min = 0;
              color.mode = "thresholds";
              thresholds = {
                mode = "absolute";
                inherit steps;
              };
            };
            overrides = [ ];
          };
          options = {
            displayMode = "gradient";
            orientation = "horizontal";
            showUnfilled = true;
            reduceOptions = {
              calcs = [ "lastNotNull" ];
              fields = "";
              values = false;
            };
          };
        };

      eCpuBusy = "100 - (avg(rate(node_cpu_seconds_total{${inst},mode=\"idle\"}[5m])) * 100)";
      eIowait = "avg(rate(node_cpu_seconds_total{${inst},mode=\"iowait\"}[5m])) * 100";
      eLoadPc = "node_load1{${inst}} / count(node_cpu_seconds_total{${inst},mode=\"idle\"}) * 100";
      eDiskUtil = "rate(node_disk_io_time_seconds_total{${inst},device=\"${disk}\"}[5m]) * 100";
      eMemUsed = "(1 - (node_memory_MemAvailable_bytes{${inst}} / node_memory_MemTotal_bytes{${inst}})) * 100";
      eMemAvail = "node_memory_MemAvailable_bytes{${inst}} / 1024^3";
      eSwapUsed = "(node_memory_SwapTotal_bytes{${inst}} - node_memory_SwapFree_bytes{${inst}}) / 1024^3";
      eSwapOut = "rate(node_vmstat_pswpout{${inst}}[5m])";
      eSwapIn = "rate(node_vmstat_pswpin{${inst}}[5m])";
      eMajflt = "rate(node_vmstat_pgmajfault{${inst}}[5m])";
      ePsiIo = "rate(node_pressure_io_waiting_seconds_total{${inst}}[5m]) * 100";
      ePsiMem = "rate(node_pressure_memory_waiting_seconds_total{${inst}}[5m]) * 100";
      ePsiCpu = "rate(node_pressure_cpu_waiting_seconds_total{${inst}}[5m]) * 100";
      pSel = extra: "{${inst}" + (if extra == "" then "" else ",${extra}") + "}";
      pTop = m: extra: "topk(10, sum by (groupname) (${m}${pSel extra}))";
      pTopRate = m: "topk(10, sum by (groupname) (rate(${m}${pSel ""}[5m])))";

      gaugesPressure = [
        (mkGauge {
          id = 10;
          title = "I/O pressure";
          expr = ePsiIo;
          gridPos = pos 0 1 4 6;
          steps = psiIo;
        })
        (mkGauge {
          id = 11;
          title = "Memory pressure";
          expr = ePsiMem;
          gridPos = pos 4 1 4 6;
          steps = psiMem;
        })
        (mkGauge {
          id = 12;
          title = "CPU pressure";
          expr = ePsiCpu;
          gridPos = pos 8 1 4 6;
          steps = psiCpu;
        })
        (mkGauge {
          id = 13;
          title = "Load per core";
          expr = eLoadPc;
          gridPos = pos 12 1 4 6;
          max = 200;
          steps = loadPc;
        })
        (mkGauge {
          id = 14;
          title = "${disk} busy";
          expr = eDiskUtil;
          gridPos = pos 16 1 4 6;
          steps = diskUtil;
        })
        (mkGauge {
          id = 15;
          title = "Memory used";
          expr = eMemUsed;
          gridPos = pos 20 1 4 6;
          steps = memUsed;
        })
      ];
      gaugesPlain = [
        (mkGauge {
          id = 10;
          title = "Load per core";
          expr = eLoadPc;
          gridPos = pos 0 1 8 6;
          max = 200;
          steps = loadPc;
        })
        (mkGauge {
          id = 11;
          title = "${disk} busy";
          expr = eDiskUtil;
          gridPos = pos 8 1 8 6;
          steps = diskUtil;
        })
        (mkGauge {
          id = 12;
          title = "Memory used";
          expr = eMemUsed;
          gridPos = pos 16 1 8 6;
          steps = memUsed;
        })
      ];
      chartLeft =
        if withPressure then
          mkTs {
            id = 20;
            title = "Pressure — % of wall time tasks lose";
            targets = [
              (mkT 0 ePsiIo "I/O")
              (mkT 1 ePsiMem "memory")
              (mkT 2 ePsiCpu "CPU")
            ];
            gridPos = pos 0 7 12 7;
            steps = psiIo;
            description = "node_pressure_* from /proc/pressure. The single best answer to which resource is stalling.";
          }
        else
          mkTs {
            id = 20;
            title = "CPU busy and iowait";
            targets = [
              (mkT 0 eCpuBusy "busy")
              (mkT 1 eIowait "iowait")
            ];
            gridPos = pos 0 7 12 7;
            description = "This kernel exposes no /proc/pressure, so busy and iowait stand in for it.";
          };
      chartRight = mkTs {
        id = 21;
        title = "Saturation — swap out/s, major faults/s, ${disk} busy %";
        targets = [
          (mkT 0 eSwapOut "swap out/s")
          (mkT 1 eMajflt "major faults/s")
          (mkT 2 eDiskUtil "${disk} busy %")
        ];
        gridPos = pos 12 7 12 7;
        unit = "short";
        steps = swapRate;
      };
      statStrip = [
        (mkStat {
          id = 30;
          title = "Blocked (D)";
          expr = "node_procs_blocked{${inst}}";
          gridPos = pos 0 14 4 5;
          unit = "short";
          decimals = 0;
          steps = blocked;
        })
        (mkStat {
          id = 31;
          title = "Runnable";
          expr = "node_procs_running{${inst}}";
          gridPos = pos 4 14 4 5;
          unit = "short";
          decimals = 0;
        })
        (mkStat {
          id = 32;
          title = "Memory available";
          expr = eMemAvail;
          gridPos = pos 8 14 4 5;
          unit = "decgbytes";
          steps = memFree;
        })
        (mkStat {
          id = 33;
          title = "Swap used";
          expr = eSwapUsed;
          gridPos = pos 12 14 4 5;
          unit = "decgbytes";
        })
        (mkStat {
          id = 34;
          title = "Load 1m";
          expr = "node_load1{${inst}}";
          gridPos = pos 16 14 4 5;
          unit = "short";
        })
        (mkStat {
          id = 35;
          title = "Uptime";
          expr = "time() - node_boot_time_seconds{${inst}}";
          gridPos = pos 20 14 4 5;
          unit = "s";
          decimals = 0;
          graphMode = "none";
        })
      ];

      yWho = 19;
      whoH = if withProcs then 16 else 0;
      whoPanels = lib.optionals withProcs [
        (mkRow 40 "Who — by program name" yWho)
        (mkTs {
          id = 41;
          title = "CPU by program";
          targets = [ (mkT 0 (pTopRate "namedprocess_namegroup_cpu_seconds_total") "{{groupname}}") ];
          gridPos = pos 0 (yWho + 1) 12 8;
          description = "Named by process-exporter matchers: firefox, kitty, claude, claude-deepseek, hyprland, ea-desktop. One series per program, not per PID and not per cgroup path.";
        })
        (mkTs {
          id = 42;
          title = "Memory by program";
          targets = [
            (mkT 0 (pTop "namedprocess_namegroup_memory_bytes" "memtype=\"resident\"") "{{groupname}}")
          ];
          gridPos = pos 12 (yWho + 1) 12 8;
          unit = "bytes";
        })
        (mkBar {
          id = 43;
          title = "Swapped out by program";
          expr = pTop "namedprocess_namegroup_memory_bytes" "memtype=\"swapped\"";
          legend = "{{groupname}}";
          gridPos = pos 0 (yWho + 9) 8 7;
          unit = "bytes";
        })
        (mkBar {
          id = 44;
          title = "Major faults/s by program";
          expr = pTopRate "namedprocess_namegroup_major_page_faults_total";
          legend = "{{groupname}}";
          gridPos = pos 8 (yWho + 9) 8 7;
          unit = "short";
          steps = swapRate;
        })
        (mkBar {
          id = 45;
          title = "Disk write/s by program";
          expr = pTopRate "namedprocess_namegroup_write_bytes_total";
          legend = "{{groupname}}";
          gridPos = pos 16 (yWho + 9) 8 7;
          unit = "Bps";
        })
      ];

      ySys = yWho + whoH;
      sysPanels = [
        (mkRow 50 "History" ySys)
        (mkTs {
          id = 51;
          title = "CPU and memory";
          targets = [
            (mkT 0 eCpuBusy "CPU %")
            (mkT 1 eMemUsed "memory %")
          ];
          gridPos = pos 0 (ySys + 1) 12 8;
        })
        (mkTs {
          id = 52;
          title = "CPU by mode";
          targets = [
            (mkT 0
              "avg by (mode) (rate(node_cpu_seconds_total{${inst},mode!~\"idle|guest|guest_nice\"}[5m])) * 100"
              "{{mode}}"
            )
          ];
          gridPos = pos 12 (ySys + 1) 12 8;
        })
        (mkTs {
          id = 53;
          title = "Disk I/O (${disk})";
          targets = [
            (mkT 0 "rate(node_disk_read_bytes_total{${inst},device=\"${disk}\"}[5m])" "read")
            (mkT 1 "rate(node_disk_written_bytes_total{${inst},device=\"${disk}\"}[5m])" "write")
          ];
          gridPos = pos 0 (ySys + 9) 12 8;
          unit = "Bps";
        })
        (mkTs {
          id = 54;
          title = "Network traffic (${nic})";
          targets = [
            (mkT 0 "rate(node_network_receive_bytes_total{${inst},device=\"${nic}\"}[5m])" "rx")
            (mkT 1 "rate(node_network_transmit_bytes_total{${inst},device=\"${nic}\"}[5m])" "tx")
          ];
          gridPos = pos 12 (ySys + 9) 12 8;
          unit = "Bps";
        })
        (mkTs {
          id = 55;
          title = "Swap traffic";
          targets = [
            (mkT 0 eSwapOut "out")
            (mkT 1 eSwapIn "in")
          ];
          gridPos = pos 0 (ySys + 17) 12 7;
          unit = "short";
          steps = swapRate;
        })
        (mkStat {
          id = 56;
          title = "RX today";
          expr = "sum(increase(node_network_receive_bytes_total{${inst},device=\"${nic}\"}[24h]))";
          gridPos = pos 12 (ySys + 17) 6 7;
          unit = "bytes";
        })
        (mkStat {
          id = 57;
          title = "TX today";
          expr = "sum(increase(node_network_transmit_bytes_total{${inst},device=\"${nic}\"}[24h]))";
          gridPos = pos 18 (ySys + 17) 6 7;
          unit = "bytes";
        })
      ];

      yEbpf = ySys + 24;
      ebpfH = if withEbpf then 10 else 0;
      ebpfPanels = lib.optionals withEbpf [
        (mkRow 60 "WAN traffic by cgroup (eBPF)" yEbpf)
        (mkTs {
          id = 61;
          title = "Top 10 cgroups — WAN TCP RX";
          targets = [
            (mkT 0 "topk(10, rate(ebpf_exporter_cgroup_wan_tcp_recv_bytes_total{${inst}}[5m]))" "{{cgroup}}")
          ];
          gridPos = pos 0 (yEbpf + 1) 12 9;
          unit = "Bps";
        })
        (mkTs {
          id = 62;
          title = "Top 10 cgroups — WAN TCP TX";
          targets = [
            (mkT 0 "topk(10, rate(ebpf_exporter_cgroup_wan_tcp_send_bytes_total{${inst}}[5m]))" "{{cgroup}}")
          ];
          gridPos = pos 12 (yEbpf + 1) 12 9;
          unit = "Bps";
        })
      ];

      yGpu = yEbpf + ebpfH;
      gpuH = if withGpu then 9 else 0;
      gpuPanels = lib.optionals withGpu [
        (mkRow 70 "GPU" yGpu)
        (mkTs {
          id = 71;
          title = "GPU utilisation";
          targets = [
            (mkT 0 "nvidia_smi_utilization_gpu_ratio{${inst}} * 100" "gpu")
            (mkT 1 "nvidia_smi_utilization_memory_ratio{${inst}} * 100" "vram")
          ];
          gridPos = pos 0 (yGpu + 1) 18 8;
        })
        (mkStat {
          id = 72;
          title = "GPU temp";
          expr = "nvidia_smi_temperature_gpu{${inst}}";
          gridPos = pos 18 (yGpu + 1) 6 8;
          unit = "celsius";
          decimals = 0;
          steps = [
            (st "green" null)
            (st "#EAB839" 70)
            (st "orange" 80)
            (st "red" 87)
          ];
        })
      ];

      yFs = yGpu + gpuH;
      fsH = if withFsUsage then 9 else 0;
      fsPanels = lib.optionals withFsUsage [
        (mkRow 80 "Filesystem" yFs)
        (mkTs {
          id = 81;
          title = "Filesystem used %";
          targets = [
            (mkT 0
              "100 * (1 - (node_filesystem_avail_bytes{${inst},fstype!~\"tmpfs|overlay|squashfs\"} / node_filesystem_size_bytes{${inst},fstype!~\"tmpfs|overlay|squashfs\"}))"
              "{{mountpoint}}"
            )
          ];
          gridPos = pos 0 (yFs + 1) 18 8;
        })
        (mkStat {
          id = 82;
          title = "Root FS free";
          expr = "node_filesystem_avail_bytes{${inst},mountpoint=\"/\"}";
          gridPos = pos 18 (yFs + 1) 6 8;
          unit = "bytes";
        })
      ];

      yDir = yFs + fsH;
      dirPanels = lib.optionals withDirsize [
        (mkRow 90 "Directory activity" yDir)
        (mkTs {
          id = 91;
          title = "Top 10 size changes (abs)";
          targets = [ (mkT 0 "topk(10, abs(delta(dirsize_bytes{${inst}}[5m])))" "{{path}}") ];
          gridPos = pos 0 (yDir + 1) 12 9;
          unit = "bytes";
        })
        (mkTs {
          id = 92;
          title = "Top 10 file count changes (abs)";
          targets = [ (mkT 0 "topk(10, abs(delta(dir_inode_count{${inst}}[5m])))" "{{path}}") ];
          gridPos = pos 12 (yDir + 1) 12 9;
          unit = "short";
        })
      ];
    in
    {
      inherit title uid refresh;
      schemaVersion = 38;
      version = 1;
      graphTooltip = 1;
      time = {
        from = "now-24h";
        to = "now";
      };
      timepicker.refresh_intervals = [
        "10s"
        "30s"
        "1m"
        "5m"
        "15m"
      ];
      panels = [
        (mkRow 1 "Right now" 0)
      ]
      ++ (if withPressure then gaugesPressure else gaugesPlain)
      ++ [
        chartLeft
        chartRight
      ]
      ++ statStrip
      ++ whoPanels
      ++ sysPanels
      ++ ebpfPanels
      ++ gpuPanels
      ++ fsPanels
      ++ dirPanels;
    };

  dashboardDesktop = mkSystemDashboard {
    title = "Mandragora Desktop";
    uid = "mandragora-desktop";
    instance = "mandragora-desktop";
    nic = "enp8s0";
    disk = "nvme0n1";
    refresh = "10s";
    withGpu = true;
    withEbpf = true;
    withDirsize = true;
    withPressure = true;
    withProcs = true;
  };

  dashboardVps = mkSystemDashboard {
    title = "Mandragora VPS";
    uid = "mandragora-vps";
    instance = "mandragora-vps";
    nic = "eth0";
    disk = "sda";
    refresh = "1m";
    withGpu = false;
    withEbpf = false;
    withDirsize = false;
    withFsUsage = true;
  };

  dashboardKindle =
    let
      inst = ''instance="mandragora-kindle"'';
      ds = {
        type = "prometheus";
        uid = "prometheus";
      };
      target = expr: legend: [
        {
          datasource = ds;
          inherit expr;
          legendFormat = legend;
          refId = "A";
        }
      ];
    in
    {
      title = "Mandragora Kindle";
      uid = "mandragora-kindle";
      schemaVersion = 38;
      version = 1;
      refresh = "5m";
      time = {
        from = "now-7d";
        to = "now";
      };
      panels = [
        {
          id = 1;
          type = "row";
          title = "Device";
          collapsed = false;
          gridPos = {
            x = 0;
            y = 0;
            w = 24;
            h = 1;
          };
        }
        {
          id = 2;
          type = "stat";
          title = "Reachable";
          gridPos = {
            x = 0;
            y = 1;
            w = 4;
            h = 4;
          };
          targets = target "kindle_up{${inst}}" "up";
          fieldConfig.defaults = {
            unit = "short";
            mappings = [
              {
                type = "value";
                options = {
                  "0" = {
                    text = "down";
                    color = "red";
                  };
                  "1" = {
                    text = "up";
                    color = "green";
                  };
                };
              }
            ];
          };
        }
        {
          id = 3;
          type = "stat";
          title = "Monitoring";
          gridPos = {
            x = 4;
            y = 1;
            w = 4;
            h = 4;
          };
          targets = target "kindle_monitor_enabled{${inst}}" "monitor";
          fieldConfig.defaults = {
            unit = "short";
            mappings = [
              {
                type = "value";
                options = {
                  "0" = {
                    text = "paused";
                    color = "text";
                  };
                  "1" = {
                    text = "on";
                    color = "green";
                  };
                };
              }
            ];
          };
        }
        {
          id = 4;
          type = "stat";
          title = "Battery";
          gridPos = {
            x = 8;
            y = 1;
            w = 4;
            h = 4;
          };
          targets = target "kindle_battery_percent{${inst}}" "battery";
          fieldConfig.defaults = {
            unit = "percent";
            min = 0;
            max = 100;
            thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "red";
                  value = null;
                }
                {
                  color = "orange";
                  value = 20;
                }
                {
                  color = "green";
                  value = 40;
                }
              ];
            };
          };
        }
        {
          id = 5;
          type = "stat";
          title = "Storage used";
          gridPos = {
            x = 12;
            y = 1;
            w = 4;
            h = 4;
          };
          targets = target "kindle_storage_used_percent{${inst}}" "used";
          fieldConfig.defaults = {
            unit = "percent";
            min = 0;
            max = 100;
          };
        }
        {
          id = 6;
          type = "stat";
          title = "Artworks";
          gridPos = {
            x = 16;
            y = 1;
            w = 4;
            h = 4;
          };
          targets = target "kindle_art_images{${inst}}" "art";
          fieldConfig.defaults.unit = "short";
        }
        {
          id = 7;
          type = "stat";
          title = "Uptime";
          gridPos = {
            x = 20;
            y = 1;
            w = 4;
            h = 4;
          };
          targets = target "kindle_uptime_seconds{${inst}}" "uptime";
          fieldConfig.defaults.unit = "s";
        }
        {
          id = 8;
          type = "row";
          title = "History";
          collapsed = false;
          gridPos = {
            x = 0;
            y = 5;
            w = 24;
            h = 1;
          };
        }
        {
          id = 9;
          type = "timeseries";
          title = "Battery";
          gridPos = {
            x = 0;
            y = 6;
            w = 12;
            h = 9;
          };
          targets = [
            {
              datasource = ds;
              expr = "kindle_battery_percent{${inst}}";
              legendFormat = "battery %";
              refId = "A";
            }
            {
              datasource = ds;
              expr = "kindle_charging{${inst}} * 100";
              legendFormat = "charging";
              refId = "B";
            }
          ];
          fieldConfig.defaults = {
            unit = "percent";
            min = 0;
            max = 100;
            custom = {
              fillOpacity = 15;
              gradientMode = "none";
            };
          };
          options = {
            legend = {
              displayMode = "list";
              placement = "bottom";
            };
            tooltip = {
              mode = "multi";
              sort = "desc";
            };
          };
        }
        {
          id = 10;
          type = "timeseries";
          title = "Services";
          gridPos = {
            x = 12;
            y = 6;
            w = 12;
            h = 9;
          };
          targets = target "kindle_service_up{${inst}}" "{{service}}";
          fieldConfig.defaults = {
            unit = "short";
            min = 0;
            max = 1;
            custom = {
              fillOpacity = 20;
              lineInterpolation = "stepAfter";
            };
          };
          options = {
            legend = {
              displayMode = "list";
              placement = "bottom";
            };
            tooltip = {
              mode = "multi";
              sort = "desc";
            };
          };
        }
        {
          id = 11;
          type = "timeseries";
          title = "Storage used";
          gridPos = {
            x = 0;
            y = 15;
            w = 12;
            h = 8;
          };
          targets = target "kindle_storage_used_percent{${inst}}" "used %";
          fieldConfig.defaults = {
            unit = "percent";
            min = 0;
            max = 100;
            custom = {
              fillOpacity = 15;
            };
          };
          options.legend = {
            displayMode = "list";
            placement = "bottom";
          };
        }
        {
          id = 12;
          type = "timeseries";
          title = "Poll duration";
          gridPos = {
            x = 12;
            y = 15;
            w = 12;
            h = 8;
          };
          targets = target "kindle_scrape_duration_seconds{${inst}}" "ssh round trip";
          fieldConfig.defaults = {
            unit = "s";
            custom = {
              fillOpacity = 10;
            };
          };
          options.legend = {
            displayMode = "list";
            placement = "bottom";
          };
        }
      ];
    };

  dashboardDir = pkgs.linkFarm "mandragora-grafana-dashboards" [
    {
      name = "mandragora-desktop.json";
      path = pkgs.writeText "mandragora-desktop.json" (builtins.toJSON dashboardDesktop);
    }
    {
      name = "mandragora-vps.json";
      path = pkgs.writeText "mandragora-vps.json" (builtins.toJSON dashboardVps);
    }
    {
      name = "mandragora-kindle.json";
      path = pkgs.writeText "mandragora-kindle.json" (builtins.toJSON dashboardKindle);
    }
  ];
in

{
  services.grafana = {
    enable = true;
    settings = {
      server = {
        protocol = "http";
        http_addr = "0.0.0.0";
        http_port = 3000;
      };
      analytics.reporting_enabled = false;
      security.secret_key = "$__file{${config.sops.secrets."grafana/secret_key".path}}";
      users.allow_sign_up = false;
      "auth" = {
        disable_login_form = true;
        disable_signout_menu = true;
      };
      "auth.basic".enabled = false;
      "auth.anonymous" = {
        enabled = true;
        org_role = "Admin";
        org_name = "Main Org.";
      };
    };
    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        deleteDatasources = [
          {
            name = "Prometheus";
            orgId = 1;
          }
        ];
        datasources = [
          {
            name = "VictoriaMetrics";
            type = "prometheus";
            url = "http://localhost:8428";
            isDefault = true;
            uid = "prometheus";
          }
          {
            name = "Loki";
            type = "loki";
            url = "http://${tailnet.vps.ip}:3100";
            uid = "loki";
            jsonData = {
              maxLines = 20000;
              timeout = 60;
            };
          }
        ];
      };
      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "mandragora";
            type = "file";
            disableDeletion = true;
            options.path = "${dashboardDir}";
          }
        ];
      };
    };
  };
}
