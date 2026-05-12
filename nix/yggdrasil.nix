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

      public-dns = {
        enable = lib.mkEnableOption "Xnode Yggdrasil Public DNS";

        domain = lib.mkOption {
          type = lib.types.str;
          default = "yggdrasil.trustless.cloud";
          example = "example.com";
          description = ''
            Port for allowing inbound peering connections. 
          '';
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.yggdrasil = {
          enable = true;
          persistentKeys = true;
          settings = {
            IfName = "ygg0";
            NodeInfo."xnode" = {
              "domains" = builtins.attrNames config.xnode.reverse-proxy.https;
            };
          };
        };
        systemd.services.yggdrasil.wants = [ "coredns.service" ];
        systemd.services.yggdrasil.startLimitIntervalSec = 0;

        services.yggdrasil.group = "xnode-dns";
        systemd.services.coredns.path = [ pkgs.yggdrasil ];
        xnode.dns.zones.".".plugins = ''
          directdns_me yggdrasil.trustless.cloud
          directdns yggdrasil.trustless.cloud
        '';

      }
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
              proxy_connect_timeout 10s;
              proxy_timeout 10s;
              resolver 127.0.0.1 ipv4=off;
              proxy_pass $backend;
              ssl_preread on;
            }
          '';
      })
      (lib.mkIf cfg.public-dns.enable {
        xnode.dns.zones.${cfg.public-dns.domain}.plugins = ''
          cache

          rewrite {
              # Add _public_dns. prefix to the root domain
              name regex ^([^.]+)\.yggdrasil\.trustless\.cloud\.$ _public_dns.{1}.${cfg.public-dns.domain}.

              # Remove _public_dns. prefix
              answer name ^_public_dns\.(.*)\.yggdrasil\.trustless\.cloud\.$ {1}.${cfg.public-dns.domain}.
          }

          directdns ${cfg.public-dns.domain}
        '';
      })
    ]
  );
}
