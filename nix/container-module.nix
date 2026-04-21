{
  config,
  options,
  lib,
  ...
}:
let
  cfg = config.xnode;
in
{
  imports = [
  ];

  options = {
    xnode.container = {
      enable = lib.mkEnableOption "run system in container";
    };
  };

  config = lib.mkIf cfg.container.enable {
    boot =
      if builtins.hasAttr "isNspawnContainer" options.boot then
        { isNspawnContainer = true; }
      else
        { isContainer = true; };

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
            LinkLocalAddressing = "no";
          };
          dhcpV4Config.UseDNS = false;
          dhcpV6Config.UseDNS = false;
        };
      };
    };

    networking.useHostResolvConf = false;
    services.resolved.enable = true;
  };
}
