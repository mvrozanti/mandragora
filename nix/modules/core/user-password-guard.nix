_:

{
  system.activationScripts.assertUserPasswordSecret = {
    deps = [ "setupSecretsForUsers" ];
    text = builtins.readFile ./assert-user-password-secret.sh;
  };

  system.activationScripts.users.deps = [ "assertUserPasswordSecret" ];
}
