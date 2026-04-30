{ config, lib, pkgs, ... }:

let
  dataDir = "/var/lib/hummingbot";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir}             0755 root root - -"
    "d ${dataDir}/conf        0755 root root - -"
    "d ${dataDir}/conf/connectors 0755 root root - -"
    "d ${dataDir}/conf/strategies 0755 root root - -"
    "d ${dataDir}/logs        0755 root root - -"
    "d ${dataDir}/data        0755 root root - -"
    "d ${dataDir}/scripts     0755 root root - -"
    "d ${dataDir}/certs       0700 root root - -"
    "d ${dataDir}/notebooks   0755 root root - -"
  ];

  virtualisation.oci-containers.containers = {
    hummingbot = {
      image = "hummingbot/hummingbot:latest";
      autoStart = true;
      volumes = [
        "${dataDir}/conf:/home/hummingbot/conf"
        "${dataDir}/logs:/home/hummingbot/logs"
        "${dataDir}/data:/home/hummingbot/data"
        "${dataDir}/scripts:/home/hummingbot/scripts"
        "${dataDir}/certs:/home/hummingbot/certs"
      ];
      extraOptions = [ "--network=host" "--tty" "--interactive" ];
    };

    hummingbot-dashboard = {
      image = "hummingbot/dashboard:latest";
      autoStart = true;
      ports = [ "127.0.0.1:8501:8501" ];
      environment.STREAMLIT_SERVER_HEADLESS = "true";
      volumes = [
        "${dataDir}/data:/home/dashboard/data"
        "${dataDir}/conf:/home/dashboard/conf"
      ];
    };

    hummingbot-jupyter = {
      image = "jupyter/scipy-notebook:latest";
      autoStart = true;
      ports = [ "127.0.0.1:8888:8888" ];
      environment.JUPYTER_ENABLE_LAB = "yes";
      volumes = [
        "${dataDir}/notebooks:/home/jovyan/work"
        "${dataDir}/data:/home/jovyan/data"
      ];
    };
  };
}
