_:

{
  services.udev.extraRules = builtins.readFile ../../snippets/rival-mouse.rules;
}
