{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.xnode.reverse-proxy;
  email =
    if (builtins.pathExists "${config.xnode.xnode-config}/email") then
      builtins.readFile "${config.xnode.xnode-config}/email"
    else
      "";
  locations = lib.mkOption {
    type = lib.types.listOf (
      lib.types.oneOf [
        (lib.types.addCheck (lib.types.submodule {
          options = {
            domain = lib.mkOption {
              type = lib.types.str;
              example = "localhost";
              description = ''
                What domain to reach this location on.
              '';
            };

            port = lib.mkOption {
              type = lib.types.port;
              example = 80;
              description = ''
                What port to reach this location on.
              '';
            };
          };
        }) (x: x ? domain && x ? port))

        (lib.types.addCheck (lib.types.submodule {
          options = {
            socket = lib.mkOption {
              type = lib.types.path;
              example = "/run/xnode-manager/.socket";
              description = ''
                What socket to reach this location on.
              '';
            };
          };
        }) (x: x ? socket))
      ]
    );
    description = ''
      How to reach the location.
    '';
  };
  http = lib.types.attrsOf (
    lib.types.attrsOf (
      lib.types.submodule {
        options = {
          inherit locations;

          protocol = lib.mkOption {
            type = lib.types.enum [
              "http"
              "https"
            ];
            default = "http";
            example = "https";
            description = ''
              Protocol to use to communicate with the location.
            '';
          };

          path = lib.mkOption {
            type = lib.types.str;
            default = "";
            example = "/";
            description = ''
              What path prefix to use to communicate with the location. This will overwrite the path prefix on the domain.
            '';
          };
        };
      }
    )
  );
in
{
  options = {
    xnode.reverse-proxy = {
      enable = lib.mkEnableOption "Xnode Reverse Proxy" // {
        default = cfg.http != { } || cfg.https != { } || cfg.tcp != { } || cfg.udp != { };
      };

      http = lib.mkOption {
        type = http;
        default = { };
        example = {
          "xnode.local"."/".locations = [ { socket = "/run/xnode-home/.socket"; } ];
        };
        description = ''
          Http locations to expose.
        '';
      };

      https = lib.mkOption {
        type = http;
        default = { };
        example = {
          "openmesh.network"."/".locations = [
            {
              domain = "localhost";
              port = "3000";
            }
          ];
          "xnode.openmesh.network" = {
            "/" = {
              protocol = "https";
              locations = [
                {
                  domain = "server1.xnode.openmesh.network";
                  port = "443";
                }
                {
                  domain = "server2.xnode.openmesh.network";
                  port = "443";
                }
                {
                  domain = "server3.xnode.openmesh.network";
                  port = "443";
                }
              ];
            };
            "/api" = {
              locations = [
                {
                  socket = "/var/lib/xnode-manager/container/xnode-backend/data/run/xnode-backend/.socket";
                }
              ];
              path = "/";
            };
          };
        };
        description = ''
          Https locations to expose.
        '';
      };

      tcp = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              inherit locations;
            };
          }
        );
        default = { };
        example = {
          "25565".locations = [
            {
              domain = "localhost";
              port = 25565;
            }
          ];
        };
        description = ''
          TCP locations to expose.
        '';
      };

      udp = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              inherit locations;
            };
          }
        );
        default = { };
        example = {
          "25565".locations = [
            {
              domain = "localhost";
              port = 25565;
            }
          ];
        };
        description = ''
          UDP locations to expose.
        '';
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Open required firewall ports for the reverse proxy to expose it's locations.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.xnode-reverse-proxy = { };
    users.users.xnode-reverse-proxy = {
      isSystemUser = true;
      group = "xnode-reverse-proxy";
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        config.services.nginx.defaultHTTPListenPort
        config.services.nginx.defaultSSLListenPort
      ]
      ++ (builtins.map lib.toInt (builtins.attrNames cfg.tcp));
      allowedUDPPorts = builtins.map lib.toInt (builtins.attrNames cfg.udp);
    };

    systemd =
      let
        sockets = builtins.map (location: location.socket) (
          builtins.filter (location: location ? socket) (
            builtins.concatMap (settings: settings.locations) (
              builtins.concatLists [
                (builtins.concatMap (paths: builtins.attrValues paths) (builtins.attrValues cfg.http))
                (builtins.concatMap (paths: builtins.attrValues paths) (builtins.attrValues cfg.https))
                (builtins.attrValues cfg.tcp)
                (builtins.attrValues cfg.udp)
              ]
            )
          )
        );
      in
      {
        paths = builtins.listToAttrs (
          builtins.map (socket: {
            name = "xnode-reverse-proxy-socket${builtins.replaceStrings [ "/" ] [ "-" ] socket}";
            value = {
              wantedBy = [ "paths.target" ];
              description = "Watch for changes to socket ${socket}.";
              pathConfig = {
                PathChanged = socket;
              };
            };
          }) sockets
        );
        services = builtins.listToAttrs (
          builtins.map (socket: {
            name = "xnode-reverse-proxy-socket${builtins.replaceStrings [ "/" ] [ "-" ] socket}";
            value = {
              description = "Allow the xnode-reverse-proxy group access to socket ${socket}";
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                if [ -S "${socket}" ]; then
                  dir="${socket}"
                  while [ "$dir" != "/" ]; do
                      # Grant execute permission to be able to traverse all directories up to the socket
                      dir=$(dirname "$dir")
                      echo "Granting x on $dir"
                      ${lib.getExe' pkgs.acl "setfacl"} --modify group:xnode-reverse-proxy:x "$dir"
                  done

                  echo "Granting rw on ${socket}"
                  ${lib.getExe' pkgs.acl "setfacl"} --modify group:xnode-reverse-proxy:rw "${socket}"
                else
                  echo "Socket doesn't exist, ignoring..."
                fi
              '';
            };
          }) sockets
          ++ [
            {
              name = "nginx";
              value = {
                startLimitIntervalSec = lib.mkForce 0;
              };
            }
          ]
        );
      };

    security.acme = {
      acceptTerms = true;
      defaults.email = if (email != "") then email else "xnode@openmesh.network";
    };

    services.nginx = {
      enable = true;
      user = "xnode-reverse-proxy";
      group = "xnode-reverse-proxy";

      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedGzipSettings = true;
      resolver.addresses = [ "127.0.0.1" ];
      proxyTimeout = "10m";
      clientMaxBodySize = "0";
      appendConfig = ''
        worker_processes auto;
      '';
      appendHttpConfig = ''
        proxy_request_buffering off;
      '';
      eventsConfig = ''
        worker_connections 2048;
      '';

      upstreams = lib.mkMerge (
        (builtins.concatMap (
          domain:
          builtins.map (
            path:
            let
              id = "http_${domain}_${builtins.replaceStrings [ "/" ] [ "<slash>" ] path}";
              locations = cfg.http.${domain}.${path}.locations;
            in
            {
              ${id} = {
                servers = lib.mkMerge (
                  builtins.map (
                    location:
                    if location ? socket then
                      { "unix:${location.socket}" = { }; }
                    else
                      {
                        "${location.domain}:${builtins.toString location.port} resolve" = { };
                      }
                  ) locations
                );
                extraConfig = ''
                  zone ${id} 64k;
                '';
              };
            }
          ) (builtins.attrNames cfg.http.${domain})
        ) (builtins.attrNames cfg.http))
        ++ (builtins.concatMap (
          domain:
          builtins.map (
            path:
            let
              id = "https_${domain}_${builtins.replaceStrings [ "/" ] [ "<slash>" ] path}";
              locations = cfg.https.${domain}.${path}.locations;
            in
            {
              ${id} = {
                servers = lib.mkMerge (
                  builtins.map (
                    location:
                    if location ? socket then
                      { "unix:${location.socket}" = { }; }
                    else
                      {
                        "${location.domain}:${builtins.toString location.port} resolve" = { };
                      }
                  ) locations
                );
                extraConfig = ''
                  zone ${id} 64k;
                '';
              };
            }
          ) (builtins.attrNames cfg.https.${domain})
        ) (builtins.attrNames cfg.https))
      );

      virtualHosts = lib.mkMerge (
        [
          {
            "_" = {
              default = true;
              rejectSSL = true;
              locations."/".return = "444";
            };
          }
        ]
        ++ (builtins.map (domain: {
          ${domain} = {
            locations = lib.mapAttrs (
              path: settings:
              let
                id = "http_${domain}_${builtins.replaceStrings [ "/" ] [ "<slash>" ] path}";
              in
              {
                proxyWebsockets = true;
                proxyPass = "${settings.protocol}://${id}${settings.path}";
              }
            ) cfg.http.${domain};
          };
        }) (builtins.attrNames cfg.http))
        ++ (builtins.map (domain: {
          ${domain} = {
            forceSSL = true;
            enableACME = true;

            locations = lib.mapAttrs (
              path: config:
              let
                id = "https_${domain}_${builtins.replaceStrings [ "/" ] [ "<slash>" ] path}";
              in
              {
                proxyWebsockets = true;
                proxyPass = "${config.protocol}://${id}${config.path}";
              }
            ) cfg.https.${domain};
          };
        }) (builtins.attrNames cfg.https))
      );

      streamConfig = builtins.concatStringsSep "\n" (
        [
          ''
            resolver 127.0.0.1;
          ''
        ]
        ++ (builtins.map (
          port:
          let
            id = "tcp_${port}";
            locations = cfg.tcp.${port}.locations;
          in
          ''
            upstream ${id} {
              zone ${id} 64k;
              ${builtins.concatStringsSep "\n" (
                builtins.map (
                  location:
                  if location ? socket then
                    "unix:${location.socket};"
                  else
                    "${location.domain}:${location.port} resolve;"
                ) locations
              )}
            }

            server {
              listen ${port};
              proxy_pass ${id};
            }
          ''
        ) (builtins.attrNames cfg.tcp))
        ++ (builtins.map (
          port:
          let
            id = "udp_${port}";
            locations = cfg.udp.${port}.locations;
          in
          ''
            upstream ${id} {
              zone ${id} 64k;
              ${builtins.concatStringsSep "\n" (
                builtins.map (
                  location:
                  if location ? socket then
                    "unix:${location.socket};"
                  else
                    "${location.domain}:${location.port} resolve;"
                ) locations
              )}
            }

            server {
              listen ${port} udp reuseport;
              proxy_pass ${id};
            }
          ''
        ) (builtins.attrNames cfg.udp))
      );
    };
  };
}
