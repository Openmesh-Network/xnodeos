{ config-dir }:
{ config, ... }:
let
  cfg = config.xnode;
  nixos-version = config.system.nixos.release;
  pinned-version =
    if (builtins.pathExists "${cfg.xnode-config}/state-version") then
      builtins.readFile "${cfg.xnode-config}/state-version"
    else
      "";
in
{
  config = {
    system.stateVersion = if pinned-version != "" then pinned-version else nixos-version;

    systemd.services.pin-state-version = {
      wantedBy = [ "multi-user.target" ];
      description = "Pin state version to first booted NixOS version.";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        if [ ! -f ${config-dir}/state-version ]; then
          echo -n ${nixos-version} > ${config-dir}/state-version
        fi
      '';
    };
  };
}
