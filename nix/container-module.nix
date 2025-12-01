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

      local-resolve = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          example = false;
          description = ''
            Use container hosted resolver instead of sharing host.
          '';
        };
      };

      mDNS = {
        resolve = lib.mkOption {
          type = lib.types.bool;
          default = true;
          example = false;
          description = ''
            Resolve mDNS (using avahi).
          '';
        };

        publish = lib.mkOption {
          type = lib.types.bool;
          default = true;
          example = false;
          description = ''
            Publish mDNS (using avahi).
          '';
        };
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

    networking.useHostResolvConf = lib.mkIf cfg.local-resolve.enable false;
    services.resolved = lib.mkIf cfg.local-resolve.enable {
      enable = true;
      llmnr = "false";
      extraConfig = ''
        MulticastDNS=no
      ''; # Avahi handles mDNS
    };
    systemd.services.systemd-resolved.serviceConfig.ProtectHome = lib.mkIf cfg.local-resolve.enable (
      lib.mkForce false
    );

    services.avahi = {
      enable = lib.mkIf (cfg.mDNS.resolve || cfg.mDNS.publish) true;
      nssmdns4 = lib.mkIf cfg.mDNS.resolve true;
      publish = lib.mkIf cfg.mDNS.publish {
        enable = true;
        addresses = true;
      };
      openFirewall = lib.mkIf cfg.mDNS.publish true;
    };
  };
}
