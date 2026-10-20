{
  sops.secrets."evm/address" = {
    sopsFile = ../../../secrets/money-wallets.yaml;
    owner = "m";
    mode = "0400";
  };
  sops.secrets."lended/cdb" = {
    sopsFile = ../../../secrets/money-lended.yaml;
    owner = "m";
    mode = "0400";
  };
}
