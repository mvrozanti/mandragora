{
  sops.secrets."binance/api_key" = {
    owner = "m";
    mode = "0400";
  };
  sops.secrets."binance/secret_key" = {
    owner = "m";
    mode = "0400";
  };
}
