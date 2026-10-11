{
  instance,
  disk,
  nic,
}:

let
  inst = ''instance="${instance}"'';
in
{
  cpuBusy = "100 - (avg(rate(node_cpu_seconds_total{${inst},mode=\"idle\"}[5m])) * 100)";
  iowait = "avg(rate(node_cpu_seconds_total{${inst},mode=\"iowait\"}[5m])) * 100";
  loadPc = "node_load1{${inst}} / count(node_cpu_seconds_total{${inst},mode=\"idle\"}) * 100";
  diskUtil = "rate(node_disk_io_time_seconds_total{${inst},device=\"${disk}\"}[5m]) * 100";
  memUsed = "(1 - (node_memory_MemAvailable_bytes{${inst}} / node_memory_MemTotal_bytes{${inst}})) * 100";
  memAvail = "node_memory_MemAvailable_bytes{${inst}} / 1024^3";
  memTotal = "node_memory_MemTotal_bytes{${inst}} / 1024^3";
  swapUsed = "(node_memory_SwapTotal_bytes{${inst}} - node_memory_SwapFree_bytes{${inst}}) / 1024^3";
  swapOut = "rate(node_vmstat_pswpout{${inst}}[5m])";
  swapIn = "rate(node_vmstat_pswpin{${inst}}[5m])";
  majflt = "rate(node_vmstat_pgmajfault{${inst}}[5m])";
  psiIo = "rate(node_pressure_io_waiting_seconds_total{${inst}}[5m]) * 100";
  psiMem = "rate(node_pressure_memory_waiting_seconds_total{${inst}}[5m]) * 100";
  psiCpu = "rate(node_pressure_cpu_waiting_seconds_total{${inst}}[5m]) * 100";
  procsBlocked = "node_procs_blocked{${inst}}";
  procsRunning = "node_procs_running{${inst}}";
  load1 = "node_load1{${inst}}";
  uptime = "time() - node_boot_time_seconds{${inst}}";
  rx = "rate(node_network_receive_bytes_total{${inst},device=\"${nic}\"}[5m])";
  tx = "rate(node_network_transmit_bytes_total{${inst},device=\"${nic}\"}[5m])";
  rxToday = "sum(increase(node_network_receive_bytes_total{${inst},device=\"${nic}\"}[24h]))";
  txToday = "sum(increase(node_network_transmit_bytes_total{${inst},device=\"${nic}\"}[24h]))";
  gpuUtil = "nvidia_smi_utilization_gpu_ratio{${inst}} * 100";
  gpuMem = "nvidia_smi_utilization_memory_ratio{${inst}} * 100";
  gpuTemp = "nvidia_smi_temperature_gpu{${inst}}";
  gpuPower = "nvidia_smi_power_draw_watts{${inst}}";
  rootFree = "node_filesystem_avail_bytes{${inst},mountpoint=\"/\"}";
  rootSize = "node_filesystem_size_bytes{${inst},mountpoint=\"/\"}";
}
