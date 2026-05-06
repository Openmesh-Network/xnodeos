{ config, lib, ... }:
let
  cfg = config.xnode.pin-state-version;
  nixos-version = config.system.nixos.release;
  pinned-version =
    if (builtins.pathExists "${config.xnode.xnode-config}/state-version") then
      builtins.readFile "${config.xnode.xnode-config}/state-version"
    else
      "";
in
{
  options = {
    xnode.pin-state-version = {
      enable = lib.mkEnableOption "automatic state version pinning" // {
        default = true;
      };

      xnode-config = lib.mkOption {
        type = lib.types.str;
        default = "${config.xnode.root}/config/xnode-config";
        example = "/config/xnode-config";
        description = ''
          xnode-config folder of the NixOS configuration.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    system.stateVersion = if pinned-version != "" then pinned-version else nixos-version;

    systemd.services.pin-state-version = {
      wantedBy = [ "multi-user.target" ];
      description = "Pin state version to first booted NixOS version.";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        if [ ! -f ${cfg.xnode-config}/state-version ]; then
          echo -n ${nixos-version} > ${cfg.xnode-config}/state-version
        fi
      '';
    };
  };
}
