{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.xnode-dns;
in
{
  options = {
    services.xnode-dns = {
      enable = lib.mkEnableOption "Enable Xnode DNS.";

      container = {
        domain = lib.mkOption {
          type = lib.types.str;
          default = "container";
          example = "lan";
          description = ''
            TLD to use for container lookup by hostname.
          '';
        };
      };

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
        extraConfig = ''
          DNSStubListener=no
          DNSStubListenerExtra=127.0.0.1:5353
        '';
      };
      services.coredns = {
        enable = true;
        config = ''
          . {
            auto {
              directory ${acme-dir}
              reload 10s
            }
            forward . 127.0.0.1:5353
          }

          ${cfg.container.domain} {
            acl {
              allow net 127.0.0.1 ::1
              block
            }
            forward . 127.0.0.1:5353
          }
        '';
      };
      systemd.services.coredns.serviceConfig = {
        User = "xnode-dns";
        Group = "xnode-dns";
        DynamicUser = lib.mkForce false;
      };

      systemd.services.dns-acme-folder = {
        wantedBy = [ "multi-user.target" ];
        description = "Create folder for ACME to populate with DNS zones.";
        serviceConfig = {
          Restart = "on-failure";
        };
        path = [
          pkgs.acl
        ];
        script = ''
          mkdir -p ${acme-dir}
          setfacl -R -m g:xnode-reverse-proxy:rw ${acme-dir}
        '';
      };

      networking = {
        nameservers = [ "127.0.0.1" ];
        firewall = {
          allowedUDPPorts = lib.mkIf cfg.openFirewall [ 53 ];
        };
      };

      systemd.network.networks = {
        "80-container-ve" = {
          matchConfig = {
            Kind = "veth";
            Name = "ve-*";
          };
          linkConfig = {
            RequiredForOnline = "no";
          };
          networkConfig = {
            Address = "0.0.0.0/32"; # Single ip address
            LinkLocalAddressing = "no";
            DHCPServer = "yes";
            IPMasquerade = "both";
            LLDP = "no";
            EmitLLDP = "no";
            IPv6AcceptRA = "no";
            IPv6SendRA = "yes";
          };
          dhcpServerConfig = {
            PersistLeases = "runtime";
            LocalLeaseDomain = cfg.container.domain;
          };
        };
      };
    };
}
