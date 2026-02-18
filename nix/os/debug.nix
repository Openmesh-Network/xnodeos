{ config, lib, ... }:
let
  debug =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/debug") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/debug"
    else
      "";
in
{
  config = lib.mkIf (debug != "") {
    # No debug disables password authentication entirely
    users.users.xnode = {
      password = debug;
      isNormalUser = true;
      extraGroups = [
        "wheel"
      ];
    };

    boot.initrd.systemd.emergencyAccess = true;
    users.users.root.password = debug;
  };
}
