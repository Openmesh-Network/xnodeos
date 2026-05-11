{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.xnode.dns;
in
{
  options = {
    xnode.dns = {
      enable = lib.mkEnableOption "Xnode DNS" // {
        default = true;
      };

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

      zones = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                domain = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                  example = "";
                  description = ''
                    FQDN filter for this zone.
                  '';
                };

                plugins = lib.mkOption {
                  type = lib.types.lines;
                  default = "";
                  example = ''
                    plugin1 arg1
                    plugin2 arg1 arg2 arg3
                  '';
                  description = ''
                    Plugin chain for this zone.
                  '';
                };
              };
            }
          )
        );
        default = { };
        example = {
          "." = ''
            forward . 1.1.1.1
          '';
        };
        description = ''
          DNS serving configuration / plugin chain.
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
        system.nssDatabases.hosts = lib.mkForce [
          "files"
          "dns"
          "resolve"
        ];
        environment.etc."resolv.conf".source = lib.mkForce (
          pkgs.writeText "resolv.conf" ''
            nameserver 127.0.0.1
          ''
        );

        services.resolved = {
          enable = true;
          settings.Resolve = {
            DNS = ""; # Prevent resolved from copying networking.nameservers
            DNSStubListener = "no";
            DNSStubListenerExtra = "127.0.0.1:5352";
          };
        };

        xnode.dns.zones.".".plugins = ''
          cache
          forward . 127.0.0.1:5352
        '';

        services.coredns = {
          enable = true;
          config = builtins.concatStringsSep "\n" (
            builtins.map (zone: ''
              ${cfg.zones.${zone}.domain} {
                ${cfg.zones.${zone}.plugins}
              }
            '') (builtins.attrNames cfg.zones)
          );
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
          ) config.xnode.reverse-proxy.http;
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
