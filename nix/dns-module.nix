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
      leases-dir = "/var/lib/systemd/network/dhcp-server-lease";
      dns-dir = "/var/lib/xnode-dns/container";
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
            auto {
              directory ${dns-dir}
              reload 10s
            }
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
        };
      };

      systemd.paths.dns-sync-container-leases = {
        wantedBy = [ "multi-user.target" ];
        description = "Trigger sync script on lease change.";
        pathConfig = {
          PathChanged = leases-dir;
        };
      };
      systemd.services.dns-sync-container-leases = {
        description = "Sync container DHCP leases with the DNS server.";
        serviceConfig = {
          Restart = "on-failure";
        };
        path = [
          pkgs.jq
        ];
        script = ''
          mkdir -p ${dns-dir}
          setfacl -R -m g:xnode-dns:r ${dns-dir}

          # Function to generate zone file content
          generate_zone() {
            local hostname="$1"
            local ip="$2"
            cat <<EOF
          $ORIGIN ''${hostname}.${cfg.container.domain}.
          @ 3600 IN SOA ${cfg.soa.nameserver}. ${
            builtins.replaceStrings [ "@" ] [ "." ] cfg.soa.mailbox
          }. $(date +"%y%d%m%H%M") ${cfg.soa.refresh} ${cfg.soa.retry} ${cfg.soa.expire} ${cfg.soa.minimumTTL}
          @ 60 IN A ''${ip}
          EOF
          }

          # Process each lease file
          for filepath in ${leases-dir}/*; do
            # Skip if not a file
            [ -f "$filepath" ] || continue

            # Try to parse JSON
            leases=$(jq -c '.Leases[]?' "$filepath" 2>/dev/null)
            if [ -z "$leases" ]; then
              echo "Skipping $filepath: invalid JSON or no leases"
              continue
            fi

            # Iterate over leases
            echo "$leases" | while read -r lease; do
              hostname=$(echo "$lease" | jq -r '.Hostname // empty')
              ip=$(echo "$lease" | jq -r '.Address | join(".") // empty')

              if [ -n "$hostname" ] && [ -n "$ip" ]; then
                  out_path="${dns-dir}/db.''${hostname}.${cfg.container.domain}"
                  generate_zone "$hostname" "$ip" > "$out_path"
                  echo "Generated zone file: $out_path"
              fi
            done
          done
        '';
      };
    };
}
