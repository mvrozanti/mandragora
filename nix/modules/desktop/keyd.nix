_: {
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        capslock = "esc";
        esc = "capslock";
      };
      settings.altgr = {
        a = "G-w";
        u = "kp7";
        i = "kp8";
        o = "kp9";
        j = "kp4";
        k = "kp5";
        l = "kp6";
        m = "kp1";
        "," = "kp2";
        "." = "kp3";
        space = "kp0";
      };
    };
  };
}
