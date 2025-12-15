{ config, lib, ... }:
let
  password =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/password") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/password"
    else
      "";
in
{
  config = lib.mkIf (password != "") {
    # No password disables password authentication entirely
    users.users.xnode = {
      password = password;
      isNormalUser = true;
      extraGroups = [
        "wheel"
      ];
    };

    services.getty = {
      greetingLine = ''<<< Welcome to Openmesh XnodeOS ${config.system.nixos.label} (\m) - \l >>>'';
    };
  };
}
