{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.xnode.yggdrasil;
in
{
  options = {
    xnode.yggdrasil = {
      enable = lib.mkEnableOption "Xnode Yggdrasil" // {
        default = true;
      };

      cache = {
        enable = lib.mkEnableOption "Xnode Yggdrasil Cache";
      };

      multicast = {
        enable = lib.mkEnableOption "Xnode Yggdrasil Multicast" // {
          default = true;
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 9002;
          description = ''
            TCP port for allowing inbound peering multicast connections. 
          '';
        };
      };

      proxy = {
        enable = lib.mkEnableOption "Xnode Yggdrasil Proxy";
      };

      peer = {
        enable = lib.mkEnableOption "Xnode Yggdrasil Peer";

        protocol = lib.mkOption {
          type = lib.types.enum [
            "tcp"
            "tls"
            "quic"
            "ws"
          ];
          default = "tls";
          description = ''
            Protocol for allowing inbound peering connections. 
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 9003;
          description = ''
            Port for allowing inbound peering connections. 
          '';
        };
      };

      dns = {
        enable = lib.mkEnableOption "Xnode Yggdrasil DNS";
      };

      public-dns = {
        enable = lib.mkEnableOption "Xnode Yggdrasil Public DNS";

        domain = lib.mkOption {
          type = lib.types.str;
          default = "yggdrasil.trustless.cloud";
          example = "example.com";
          description = ''
            Domain to public DNS. 
          '';
        };
      };

      xnode-info = {
        xnode-auth = {
          enable = lib.mkEnableOption "Set Xnode Auth of Xnode Info to Yggdrasil IP" // {
            default = true;
          };
        };
        dns = {
          enable = lib.mkEnableOption "Publish Yggdrasil DirectDNS domain to Xnode Info" // {
            default = builtins.pathExists "${config.xnode.xnode-config}/domain";
          };

          domain =
            lib.mkOption {
              type = lib.types.str;
              example = "example.com";
              description = ''
                Domain to CNAME to our Yggdrasil DirectDNS domain.
              '';
            }
            // (
              if (builtins.pathExists "${config.xnode.xnode-config}/domain") then
                { default = builtins.readFile "${config.xnode.xnode-config}/domain"; }
              else
                { }
            );
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        users.groups.yggdrasil = { };
        users.users.yggdrasil = {
          isSystemUser = true;
          group = "yggdrasil";
        };

        services.yggdrasil = {
          enable = true;
          group = "yggdrasil";
          persistentKeys = true;
          settings = {
            IfName = "ygg0";
            NodeInfo."xnode" = {
              "domains" = builtins.attrNames config.xnode.reverse-proxy.https;
            };
          };
        };
        systemd.services.yggdrasil.wants = [ "coredns.service" ]; # Make sure DNS resolver is up before starting yggdrasil
        systemd.services.yggdrasil.startLimitIntervalSec = 0;

        users.users.${config.systemd.services.coredns.serviceConfig.User}.extraGroups = [
          config.services.yggdrasil.group
        ];
        systemd.services.coredns.path = [ pkgs.yggdrasil ];
        xnode.dns.zones.".".plugins = ''
          directdns_me yggdrasil.trustless.cloud
          directdns yggdrasil.trustless.cloud
        '';

        networking.getaddrinfo = {
          enable = true;
          label = {
            "200::/7" = 99;
          };
          precedence = {
            "200::/7" = 45;
          };
        };
        systemd.network.networks."99-yggdrasil" = {
          matchConfig.Name = config.services.yggdrasil.settings.IfName;
          ipv6AddressLabels = [
            {
              Label = 99;
              Prefix = "200::/7";
            }
          ];
          networkConfig = {
            KeepConfiguration = "yes";
          };
        };
      }
      (lib.mkIf cfg.cache.enable {
        nixpkgs.config = {
          contentAddressedByDefault = true;
          enableParallelBuildingByDefault = true;
          strictDepsByDefault = true;
        };
        nix.settings = {
          experimental-features = [ "ca-derivations" ];
          require-sigs = false;
          accept-flake-config = lib.mkForce false;
          substituters = lib.mkForce [ ]; # Add localhost binary cache server
          trusted-public-keys = lib.mkForce [ ];
        };
        # Enable nix-serve / attic / harmonia like binary cache server
        # App:
        # 1. [If request does not come from localhost or multicast local yggdrasil peer], reject
        # 2. Check local store
        # 3. Ask multicast local yggdrasil peer
        # OS:
        # 1. Check local store
        # 2. [If incoming from multicast local yggdrasil peer], ask all _other_ multicast local yggdrasil peers
        # 3. Kademlia overlay query to find nodes that serve this binary cache item (OS only, app will go through OS on step 2)
      })
      (lib.mkIf cfg.multicast.enable {
        services.yggdrasil = {
          openMulticastPort = true;
          settings = {
            MulticastInterfaces = lib.mkIf cfg.multicast.enable [
              {
                "Regex" = "^(en.*|wl.*|host.*|ns.*|ve-.*|vt-.*)$";
                "Beacon" = true;
                "Listen" = true;
                "Port" = cfg.multicast.port;
              }
            ];
          };
        };
        networking.firewall.allowedTCPPorts = [ cfg.multicast.port ];
      })
      (lib.mkIf cfg.peer.enable {
        services.yggdrasil.settings.Listen = [
          "${cfg.peer.protocol}://0.0.0.0:${builtins.toString cfg.peer.port}"
          "${cfg.peer.protocol}://[::]:${builtins.toString cfg.peer.port}"
        ];
        networking.firewall.allowedTCPPorts = [ cfg.peer.port ];
      })
      (lib.mkIf cfg.proxy.enable {
        services.nginx.virtualHosts."_" = lib.mkForce {
          default = true;
          locations."/".extraConfig = ''
            resolver 127.0.0.1 ipv4=off;
            proxy_pass http://$host$request_uri;
          '';
        };
        services.nginx.defaultSSLListenPort = 8443;
        networking.firewall.allowedTCPPorts = [ 443 ];
        services.nginx.streamConfig =
          let
            domains = builtins.attrNames config.xnode.reverse-proxy.https;
          in
          ''
            map $ssl_preread_server_name $backend {
                ${builtins.concatStringsSep "                \n" (
                  builtins.map (
                    domain: "${domain} localhost:${builtins.toString config.services.nginx.defaultSSLListenPort};"
                  ) domains
                )}
                default $ssl_preread_server_name:443;
            }

            server {
              listen 0.0.0.0:443;
              listen [::]:443;
              resolver 127.0.0.1 ipv4=off;
              proxy_pass $backend;
              ssl_preread on;
            }
          '';
      })
      (lib.mkIf cfg.dns.enable {
        xnode.dns.zones.".".plugins = ''
          finalize
        '';
      })
      (lib.mkIf cfg.public-dns.enable {
        xnode.dns.zones.${cfg.public-dns.domain}.plugins =
          let
            escapedPublicDNSDomain = builtins.replaceStrings [ "." ] [ "\." ] cfg.public-dns.domain;
          in
          ''
            cache

            rewrite {
                # Add _public_dns. prefix to the root domain
                name regex ^([^.]+)\.${escapedPublicDNSDomain}\.$ _public_dns.{1}.${cfg.public-dns.domain}.

                # Remove _public_dns. prefix
                answer name ^_public_dns\.(.*)\.${escapedPublicDNSDomain}\.$ {1}.${cfg.public-dns.domain}.
            }

            directdns ${cfg.public-dns.domain}
          '';
      })
      (lib.mkIf cfg.xnode-info.xnode-auth.enable {
        systemd.services.xnode-info-xnode-auth-yggdrasil = {
          wantedBy = [ "multi-user.target" ];
          requires = [ "yggdrasil.service" ];
          after = [ "yggdrasil.service" ];
          description = "Set Xnode Auth of Xnode Info to Yggdrasil IP";
          serviceConfig = {
            Type = "oneshot";
            User = "xnode-info";
            Group = "xnode-info";
          };
          path = [
            pkgs.iproute2
            pkgs.jq
          ];
          script = ''
            ifname=${config.services.yggdrasil.settings.IfName}
            ipv6=""

            for i in $(seq 1 60); do
              ipv6=$(ip -j -6 addr show dev "$ifname" 2>/dev/null \
                | jq -r '.[0].addr_info[]? | select(.scope=="global") | .local // empty' \
                | head -n1)
              if [ -n "$ipv6" ]; then
                break
              fi
              sleep 1
            done

            if [ -z "$ipv6" ]; then
              echo "Timed out waiting for a global Yggdrasil address on $ifname" >&2
              exit 1
            fi

            echo -n "ip:$ipv6" > /xnode-info/xnode-auth
          '';
        };
      })
      (lib.mkIf cfg.xnode-info.dns.enable {
        systemd.services.xnode-info-dns-yggdrasil = {
          wantedBy = [ "multi-user.target" ];
          requires = [ "yggdrasil.service" ];
          after = [ "yggdrasil.service" ];
          description = "Publish Yggdrasil DirectDNS domain to Xnode Info";
          serviceConfig = {
            Type = "oneshot";
            User = "xnode-info";
            Group = "xnode-info";
          };
          path = [
            pkgs.iproute2
            pkgs.jq
          ];
          script = ''
            ifname=${config.services.yggdrasil.settings.IfName}
            ipv6=""

            for i in $(seq 1 60); do
              ipv6=$(ip -j -6 addr show dev "$ifname" 2>/dev/null \
                | jq -r '.[0].addr_info[]? | select(.scope=="global") | .local // empty' \
                | head -n1)
              if [ -n "$ipv6" ]; then
                break
              fi
              sleep 1
            done

            if [ -z "$ipv6" ]; then
              echo "Timed out waiting for a global Yggdrasil address on $ifname" >&2
              exit 1
            fi

            cat > /xnode-info/dns/yggdrasil.json <<EOF
            {
              "records": [
                {
                  "type": "cname",
                  "name": "${cfg.xnode-info.dns.domain}",
                  "value": "''${ipv6//:/-}.yggdrasil.trustless.cloud"
                }
              ]
            }
            EOF
          '';
        };
      })
    ]
  );
}
