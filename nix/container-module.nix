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

    nix.settings.sandbox = false;

    networking = {
      useDHCP = false;
      useNetworkd = true;
      nftables.enable = true;
      firewall.allowedUDPPorts = [ 5355 ];
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
            Virtualization = "container";
          };
          networkConfig = {
            DHCP = "yes";
            LinkLocalAddressing = "yes";
            LLDP = "yes";
            EmitLLDP = "customer-bridge";
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
