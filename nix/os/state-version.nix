{ config, ... }:
let
  nixosVersion = config.system.nixos.release;
  pinnedVersion =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/state-version") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/state-version"
    else
      "";
in
{
  config = {
    system.stateVersion = if pinnedVersion != "" then pinnedVersion else nixosVersion;

    systemd.services.pin-state-version =
      let
        nixosConfigDir = "/etc/nixos/xnode-config";
      in
      {
        wantedBy = [ "multi-user.target" ];
        description = "Pin state version to first booted NixOS version.";
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          if [ ! -f ${nixosConfigDir}/state-version ]; then
            echo -n ${nixosVersion} > ${nixosConfigDir}/state-version
          fi
        '';
      };
  };
}
