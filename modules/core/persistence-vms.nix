{ ... }:

{
  environment.persistence."/persistent" = {
    directories = [
      "/var/lib/libvirt"
      "/var/lib/swtpm"
    ];
  };
}
