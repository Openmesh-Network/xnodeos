{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.services.xnode-container;
in
{
  options = {
    services.xnode-container = {
      xnode-config = lib.mkOption {
        type = lib.types.path;
        example = ./xnode-config;
        description = ''
          Folder with configuration files.
        '';
      };
    };
  };

  config = {
    boot =
      if builtins.hasAttr "isNspawnContainer" options.boot then
        { isNspawnContainer = true; }
      else
        { isContainer = true; };

    nixpkgs.hostPlatform =
      if (builtins.pathExists "${cfg.xnode-config}/host-platform") then
        builtins.readFile "${cfg.xnode-config}/host-platform"
      else
        "x86_64-linux";

    system.stateVersion =
      if (builtins.pathExists "${cfg.xnode-config}/state-version") then
        builtins.readFile "${cfg.xnode-config}/state-version"
      else
        config.system.nixos.release;

    systemd.services.pin-state-version = {
      wantedBy = [ "multi-user.target" ];
      description = "Pin state version to first booted NixOS version.";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        if [ ! -f /xnode-config/state-version ]; then
          echo -n ${config.system.nixos.release} > /xnode-config/state-version
        fi
      '';
    };

    networking.hostName = lib.mkIf (builtins.pathExists "${cfg.xnode-config}/hostname") (
      builtins.readFile "${cfg.xnode-config}/hostname"
    );

    networking = {
      useDHCP = false;
      useNetworkd = true;
    };
    systemd.network = {
      enable = true;
      wait-online = {
        timeout = 10;
        anyInterface = true;
      };
      networks = {
        "80-container-host0" = {
          matchConfig.Name = "host*";
          networkConfig = {
            DHCP = "yes";
          };
          dhcpV4Config.RouteMetric = 100;
          dhcpV6Config.WithoutRA = "solicit";
        };
      };
    };

    networking.useHostResolvConf = false;
    services.resolved.enable = true;
  };
}
