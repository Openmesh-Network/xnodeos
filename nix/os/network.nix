{ config, lib, ... }:
let
  cfg = config.xnode;
  raw-network-config =
    if (builtins.pathExists "${cfg.xnode-config}/network") then
      builtins.fromJSON (builtins.readFile "${cfg.xnode-config}/network")
    else
      {
        address = [ ];
        route = [ ];
      };
  network-config = builtins.filter (network: network.value.ip != [ ] || network.value.route != [ ]) (
    builtins.map (address: {
      name = address.address;
      value = {
        ip = builtins.map (ip: { address = "${ip.local}/${builtins.toString ip.prefixlen}"; }) (
          builtins.filter (ip: (ip.scope or "global") == "global" && !(ip.dynamic or false)) address.addr_info
        );
        route =
          builtins.map
            (route: {
              destination = if (route.dst == "default") then "0.0.0.0/0" else route.dst;
              gateway = route.gateway or null;
              onlink = builtins.elem "onlink" (route.flags or [ ]);
            })
            (
              builtins.filter (
                route: (route.protocol or "boot") == "static" && route.dev == address.ifname
              ) raw-network-config.route
            );
      };
    }) raw-network-config.address
  );
in
{
  config = lib.mkMerge [
    {
      networking = {
        useDHCP = false;
        useNetworkd = true;
        wireless.iwd = {
          enable = true;
        };
        nftables.enable = true;
        firewall = {
          interfaces."ns-*".allowedUDPPorts = [
            67
            5355
          ];
          interfaces."ve-*".allowedUDPPorts = [
            67
            5355
          ];
          interfaces."vt-*".allowedUDPPorts = [
            67
            5355
          ];
        };
      };

      systemd.network = {
        enable = true;
        wait-online = {
          timeout = 10;
          anyInterface = true;
        };
        networks = {
          "89-ethernet" = {
            matchConfig = {
              Kind = "!*";
              Type = "ether";
            };
            networkConfig = {
              DHCP = "yes";
            };
            dhcpV4Config.UseDNS = false;
            dhcpV6Config.UseDNS = false;
            dhcpV4Config.RouteMetric = 100;
            ipv6AcceptRAConfig.RouteMetric = 100;
          };
          "80-wifi-station" = {
            matchConfig = {
              Type = "wlan";
              WLANInterfaceType = "station";
            };
            networkConfig = {
              DHCP = "yes";
            };
            dhcpV4Config.UseDNS = false;
            dhcpV6Config.UseDNS = false;
            dhcpV4Config.RouteMetric = 200;
            ipv6AcceptRAConfig.RouteMetric = 200;
          };
          "80-wifi-ap" = {
            matchConfig = {
              Type = "wlan";
              WLANInterfaceType = "ap";
            };
            networkConfig = {
              Address = "0.0.0.0/24";
              DHCPServer = "yes";
              IPMasquerade = "both";
              IPv6AcceptRA = "no";
              IPv6SendRA = "yes";
            };
            dhcpServerConfig = {
              LocalLeaseDomain = "home.arpa";
            };
          };
          "80-namespace-ns" = {
            matchConfig = {
              Kind = "veth";
              Name = "ns-*";
            };
            linkConfig = {
              RequiredForOnline = "no";
            };
            networkConfig = {
              Address = "0.0.0.0/28";
              LinkLocalAddressing = "yes";
              DHCPServer = "yes";
              IPMasquerade = "both";
              LLDP = "yes";
              EmitLLDP = "customer-bridge";
              IPv6AcceptRA = "no";
              IPv6SendRA = "yes";
            };
            dhcpServerConfig = {
              PersistLeases = "runtime";
              LocalLeaseDomain = "container.internal";
            };
          };
          "80-container-ve" = {
            matchConfig = {
              Kind = "veth";
              Name = "ve-*";
            };
            linkConfig = {
              RequiredForOnline = "no";
            };
            networkConfig = {
              Address = "0.0.0.0/28";
              LinkLocalAddressing = "yes";
              DHCPServer = "yes";
              IPMasquerade = "both";
              LLDP = "yes";
              EmitLLDP = "customer-bridge";
              IPv6AcceptRA = "no";
              IPv6SendRA = "yes";
            };
            dhcpServerConfig = {
              PersistLeases = "runtime";
              LocalLeaseDomain = "container.internal";
            };
          };
          "80-vm-vt" = {
            matchConfig = {
              Kind = "tun";
              Name = "vt-*";
            };
            linkConfig = {
              RequiredForOnline = "no";
            };
            networkConfig = {
              Address = "0.0.0.0/28";
              LinkLocalAddressing = "yes";
              DHCPServer = "yes";
              IPMasquerade = "both";
              LLDP = "yes";
              EmitLLDP = "customer-bridge";
              IPv6AcceptRA = "no";
              IPv6SendRA = "yes";
            };
            dhcpServerConfig = {
              PersistLeases = "runtime";
              LocalLeaseDomain = "virtual-machine.internal";
            };
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
            routes = builtins.map (
              route:
              {
                Destination = route.destination;
                GatewayOnLink = if (route.onlink) then "yes" else "no";
              }
              // (lib.optionalAttrs (route.gateway != null) {
                Gateway = route.gateway;
              })
            ) interface.value.route;
          };
        }) network-config
      );
    }
  ];
}
