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

      soa = {
        nameserver = lib.mkOption {
          type = lib.types.str;
          example = "plopmenz.openmesh.cloud";
          description = ''
            The nameserver pointing to this machine.
          '';
        };

        mailbox = lib.mkOption {
          type = lib.types.str;
          default = config.security.acme.defaults.email;
          description = ''
            The mailbox of the person responsible for this domain (zone).
          '';
        };

        refresh = lib.mkOption {
          type = lib.types.str;
          default = "7200";
          description = ''
            A 32 bit time interval before the zone should be refreshed.
          '';
        };

        retry = lib.mkOption {
          type = lib.types.str;
          default = "3600";
          description = ''
            A 32 bit time interval that should elapse before a failed refresh should be retried.
          '';
        };

        expire = lib.mkOption {
          type = lib.types.str;
          default = "1209600";
          description = ''
            A 32 bit time value that specifies the upper limit on the time interval that can elapse before the zone is no longer authoritative.
          '';
        };

        minimumTTL = lib.mkOption {
          type = lib.types.str;
          default = "3600";
          description = ''
            The unsigned 32 bit minimum TTL field that should be exported with any RR from this zone.
          '';
        };
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

  config =
    let
      acme-dir = "/var/lib/xnode-dns/acme";
    in
    lib.mkIf cfg.enable {
      users.groups.xnode-dns = { };
      users.users.xnode-dns = {
        isSystemUser = true;
        group = "xnode-dns";
        home = "/var/lib/xnode-dns";
        createHome = true;
      };

      services.resolved = {
        enable = true;
        settings.Resolve = {
          DNSStubListener = "no";
          DNSStubListenerExtra = "127.0.0.1:5352";
        };
      };

      services.coredns = {
        enable = true;
        config = ''
          . {
            auto {
              directory ${acme-dir}
              reload 10s
            }
            forward . 127.0.0.1:5352
          }

          internal. {
            acl {
              allow net 127.0.0.1 ::1
              block
            }
            rewrite name suffix .internal. . answer auto
            forward . 127.0.0.1:5352
          }
        '';
      };
      systemd.services.coredns.serviceConfig = {
        User = "xnode-dns";
        Group = "xnode-dns";
        DynamicUser = lib.mkForce false;
      };

      systemd.tmpfiles.rules = [
        "d ${acme-dir} - - - - -"
        "A ${acme-dir} - - - - g:xnode-reverse-proxy:rw"
      ];

      networking.firewall.allowedUDPPorts = lib.mkIf cfg.openFirewall [ 53 ];
    }
    // (lib.mkIf cfg.mdns.enable {
      services.resolved.settings.Resolve."MulticastDNS" = "yes";
      systemd.network.networks."89-ethernet".networkConfig."MulticastDNS" = "yes";
      systemd.network.networks."80-wifi-station".networkConfig."MulticastDNS" = "yes";
      networking.firewall.allowedUDPPorts = lib.mkIf cfg.mdns.openFirewall [ 5353 ];
    });
}
