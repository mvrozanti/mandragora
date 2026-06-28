_:

{
  systemd.user.slices."im-gen" = {
    description = "Combined cap for im-gen-web + im-gen-bot (sum-bounded RAM)";
    sliceConfig = {
      MemoryMax = "18G";
      MemorySwapMax = "0";
      ManagedOOMSwap = "kill";
      ManagedOOMMemoryPressure = "kill";
    };
  };
}
