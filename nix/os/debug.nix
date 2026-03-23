{ config, lib, ... }:
let
  cfg = config.xnode;
  debug =
    if (builtins.pathExists "${cfg.xnode-config}/debug") then
      builtins.readFile "${cfg.xnode-config}/debug"
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
