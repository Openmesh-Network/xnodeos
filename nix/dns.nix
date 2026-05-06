{
  config,
  lib,
  ...
}:
let
  cfg = config.services.xnode-dns;
in
{
  options = {
    services.xnode-dns = {
      enable = lib.mkEnableOption "Xnode DNS";

      mdns = {
        enable = lib.mkEnableOption "Xnode Multicast DNS";

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          example = false;
          description = ''
            Allow multicast DNS traffic to go through firewall.
          '';
        };
      };

      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = ''
          directdns yggdrasil.trustless.cloud.
        '';
        description = ''
          Extra config to add to root block of coredns.
        '';
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Allow DNS traffic to go through firewall.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        users.groups.xnode-dns = { };
        users.users.xnode-dns = {
          isSystemUser = true;
          group = "xnode-dns";
        };

        networking.nameservers = [ "127.0.0.1" ];

        services.resolved = {
          enable = true;
          settings.Resolve = {
            DNS = [ ]; # Prevent resolved from copying networking.nameservers
            DNSStubListener = "no";
            DNSStubListenerExtra = "127.0.0.1:5352";
          };
        };

        services.coredns = {
          enable = true;
          config = ''
            . {
              ${cfg.extraConfig}
              forward . 127.0.0.1:5352
            }
          '';
        };
        systemd.services.coredns.serviceConfig = {
          User = "xnode-dns";
          Group = "xnode-dns";
          DynamicUser = lib.mkForce false;
        };

        networking.firewall.allowedUDPPorts = lib.mkIf cfg.openFirewall [ 53 ];
        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 53 ];
      }
      (
        let
          mdns-domains = lib.filterAttrs (
            domain: settings: lib.strings.hasSuffix ".local" domain
          ) config.services.xnode-reverse-proxy.http;
          dnssd = builtins.map (domain: lib.strings.removeSuffix ".local" domain) (
            builtins.attrNames mdns-domains
          );
        in
        lib.mkIf cfg.mdns.enable {
          services.resolved.settings.Resolve."MulticastDNS" = "yes";
          systemd.network.networks."89-ethernet".networkConfig."MulticastDNS" = "yes";
          systemd.network.networks."80-wifi-station".networkConfig."MulticastDNS" = "yes";
          networking.firewall.allowedUDPPorts = lib.mkIf cfg.mdns.openFirewall [ 5353 ];

          environment.etc = lib.mkMerge (
            builtins.map (item: {
              "systemd/dnssd/${item}.dnssd".text = ''
                [Service]
                Name=${item}
                Type=_http._tcp
                Port=80
              '';
            }) dnssd
          );
          systemd.services.systemd-resolved.reloadTriggers = builtins.map (
            item: config.environment.etc."systemd/dnssd/${item}.dnssd".source
          ) dnssd;
        }
      )
    ]
  );
}
