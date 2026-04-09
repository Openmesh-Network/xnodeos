{
  config,
  options,
  ...
}:
let
  cfg = config.xnode;
in
{
  imports = [
    ./xnode-config.nix
    ./state-version.nix
    ./name.nix
    ./auto-update.nix
  ];

  config = {
    xnode = {
      root = "/";
      auto-update.enable = true;
      pin-state-version.enable = true;
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
