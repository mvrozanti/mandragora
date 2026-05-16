{ config, lib, pkgs, ... }:

{
  systemd.user.slices."im-gen" = {
    description = "Combined cap for im-gen-web + im-gen-bot (sum-bounded RAM)";
    sliceConfig = {
      MemoryMax = "22G";
      MemorySwapMax = "0";
      ManagedOOMSwap = "kill";
      ManagedOOMMemoryPressure = "kill";
    };
  };
}
