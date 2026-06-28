_:

{
  nixpkgs.overlays = [
    (_final: prev: {
      openldap = prev.openldap.overrideAttrs (_oldAttrs: {
        doCheck = false;
      });
    })
  ];
}
