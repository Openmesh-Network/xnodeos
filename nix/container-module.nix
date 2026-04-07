{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.xnode;
in
{
  imports = [
    ./xnode-config.nix
    (import ./state-version.nix { config-dir = "/config/xnode-config"; })
    ./name.nix
    ./auto-update.nix
  ];

  config = {
    xnode.auto-update = {
      enable = true;
      root = "/";
    };

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
          matchConfig = {
            Kind = "veth";
            Name = "host0";
          };
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = "no";
          };
          dhcpV4Config.RouteMetric = 100;
        };
      };
    };

    networking.useHostResolvConf = false;
    services.resolved.enable = true;
  };
}
