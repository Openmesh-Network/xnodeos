{ config, lib, ... }:
let
  raw-network-config =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/network") then
      builtins.fromJSON (builtins.readFile "${config.services.xnodeos.xnode-config}/network")
    else
      {
        address = [ ];
        route = [ ];
      };
  network-config = builtins.map (address: {
    name = address.address;
    value = {
      ip = builtins.map (ip: { address = "${ip.local}/${builtins.toString ip.prefixlen}"; }) (
        builtins.filter (ip: ip.scope == "global" && !(ip.dynamic or false)) address.addr_info
      );
      route =
        builtins.map
          (route: {
            destination = if (route.dst == "default") then "0.0.0.0/0" else route.dst;
            gateway = route.gateway;
            onlink = builtins.elem "onlink" route.flags;
          })
          (
            builtins.filter (
              route: route.protocol == "static" && route.dev == address.ifname
            ) raw-network-config.route
          );
    };
  }) raw-network-config.address;
in
{
  config = lib.mkMerge [
    {
      networking = {
        hostName = "xnode";
        useDHCP = false;
        useNetworkd = true;
        wireless.iwd = {
          enable = true;
        };
      };

      systemd.network = {
        enable = true;
        wait-online = {
          timeout = 10;
          anyInterface = true;
        };
        networks = {
          "99-wired" = {
            matchConfig.Name = "en*";
            networkConfig = {
              DHCP = "yes";
            };
            dhcpV4Config.RouteMetric = 100;
            dhcpV6Config.WithoutRA = "solicit";
          };
          "99-wireless" = {
            matchConfig.Name = "wl*";
            networkConfig = {
              DHCP = "yes";
            };
            dhcpV4Config.RouteMetric = 200;
            dhcpV6Config.WithoutRA = "solicit";
          };
        };
      };
    }
    {
      systemd.network.networks = builtins.listToAttrs (
        builtins.map (interface: {
          name = "00-${interface.name}";
          value = {
            matchConfig.MACAddress = interface.name;
            networkConfig = {
              DHCP = "yes";
              LLDP = "yes";
              IPv6AcceptRA = "yes";
              MulticastDNS = "yes";
            };
            address = builtins.map (ip: ip.address) interface.value.ip;
            routes = builtins.map (route: {
              Destination = route.destination;
              Gateway = route.gateway;
              GatewayOnLink = if (route.onlink) then "yes" else "no";
            }) interface.value.route;
          };
        }) network-config
      );
    }
  ];
}
