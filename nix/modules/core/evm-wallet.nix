{
  sops.secrets."evm/address" = {
    sopsFile = ../../../secrets/money-wallets.yaml;
    owner = "m";
    mode = "0400";
  };
}
