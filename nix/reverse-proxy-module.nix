{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.xnode-reverse-proxy;
  locations = lib.mkOption {
    type = lib.types.listOf (
      lib.types.oneOf [
        (lib.types.addCheck (lib.types.submodule {
          options = {
            domain = lib.mkOption {
              type = lib.types.str;
              example = "app.container.internal";
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
    services.xnode-reverse-proxy = {
      enable = lib.mkEnableOption "Xnode Reverse Proxy";

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
              domain = "openmesh-landing-page.container.internal";
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
              domain = "minecraft-server.container";
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
              domain = "minecraft-server.container";
              port = 25565;
            }
          ];
        };
        description = ''
          UDP locations to expose.
        '';
      };

      certificates = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              domain = lib.mkOption {
                type = lib.types.str;
                example = "*.plopmenz.openmesh.network";
                description = ''
                  The domain to request a certificate for.
                '';
              };
            };
          }
        );
        default = { };
        example = {
          "plopmenz.openmesh.network" = {
            domain = "plopmenz.openmesh.network";
          };
          "plopmenz.openmesh.network-wildcard" = {
            domain = "*.plopmenz.openmesh.network";
          };
        };
        description = ''
          All certificates to request using the DNS challenge. All domains in rules get a dedicated certificate automatically using the HTTP challenge, except when matching a domain or wildcard in this list.
        '';
      };

      cloudflared = {
        enable = lib.mkEnableOption "expose through cloudflared";

        tunnel = {
          name = lib.mkOption {
            type = lib.types.str;
            default = "xnode";
            example = "MyXnode";
            description = ''
              Name of the Cloudflare tunnel to create and connect to.
            '';
          };
        };
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

  config =
    let
      data = "/var/lib/xnode-reverse-proxy";
    in
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          users.groups.xnode-reverse-proxy = { };
          users.users.xnode-reverse-proxy = {
            isSystemUser = true;
            group = "xnode-reverse-proxy";
            home = data;
            createHome = true;
          };

          networking.firewall = lib.mkIf cfg.openFirewall {
            allowedTCPPorts = [
              80
              443
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
              );
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
            appendConfig = ''
              worker_processes auto;
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
                              "${location.domain}:${location.port} resolve" = { };
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
                }
                //
                  # Use existing acme if defined for this domain, otherwise generate it using enableACME
                  (
                    let
                      wildcard = builtins.replaceStrings [ builtins.head (lib.splitString "." domain) ] [ "*" ] (domain);
                      acme-wildcard = builtins.filter (cert: cert.value.domain == wildcard) (
                        lib.attrsets.attrsToList cfg.certificates
                      );
                      acme-exact = builtins.filter (cert: cert.value.domain == domain) (
                        lib.attrsets.attrsToList cfg.certificates
                      );
                      acme =
                        if builtins.length acme-exact == 0 then
                          (if builtins.length acme-wildcard == 0 then null else builtins.head acme-wildcard)
                        else
                          builtins.head acme-exact;
                    in
                    (
                      if builtins.isNull acme then
                        {
                          enableACME = true;
                        }
                      else
                        {
                          useACMEHost = acme.name;
                        }
                    )
                  );
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

          security.acme.certs = builtins.mapAttrs (name: value: {
            domain = value.domain;
            group = "xnode-reverse-proxy";
            dnsProvider = "exec";
            environmentFile =
              let
                dns-dir = "/var/lib/xnode-dns/acme";
              in
              pkgs.writeText "acme-env" "EXEC_PATH=${pkgs.writeScript "acme-dns-update.sh" ''
                mode="$1"
                record="$2"
                token="$3"

                if [ "$mode" = "present" ]; then
                    cat > ${dns-dir}/db.$record << EOL
                $ORIGIN $record
                @ 3600 IN SOA ${config.services.xnode-dns.soa.nameserver}. ${
                  builtins.replaceStrings [ "@" ] [ "." ] config.services.xnode-dns.soa.mailbox
                }. $(date +"%y%d%m%H%M") ${config.services.xnode-dns.soa.refresh} ${config.services.xnode-dns.soa.retry} ${config.services.xnode-dns.soa.expire} ${config.services.xnode-dns.soa.minimumTTL}
                @ IN 10 TXT "$token"
                EOL
                    sleep 10s
                else
                    rm ${dns-dir}/db.$record;
                fi
              ''}";
            dnsPropagationCheck = false;
          }) cfg.certificates;
        }
        (lib.mkIf cfg.cloudflared.enable {
          systemd.services.cloudflared-login = {
            wantedBy = [ "multi-user.target" ];
            description = "Authenticate cloudflared with your account.";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            serviceConfig = {
              User = "xnode-reverse-proxy";
              Group = "xnode-reverse-proxy";
              Restart = "on-failure";
            };
            script = ''
              ${lib.getExe pkgs.cloudflared} tunnel login
            '';
          };

          systemd.paths.cloudflared-tunnel-xnode-create = {
            wantedBy = [ "paths.target" ];
            pathConfig = {
              PathChanged = "${data}/.cloudflared/cert.pem";
              Unit = "cloudflared-tunnel-xnode-create.service";
            };
          };
          systemd.services.cloudflared-tunnel-xnode-create = {
            description = "Create locally managed xnode tunnel.";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            serviceConfig = {
              User = "xnode-reverse-proxy";
              Group = "xnode-reverse-proxy";
              Restart = "on-failure";
            };
            script = ''
              ${lib.getExe pkgs.cloudflared} tunnel create "${cfg.cloudflared.tunnel.name}"
              for f in ${data}/.cloudflared/*.json ; do mv "$f" "${data}/.cloudflared/tunnel.json"; done
            '';
          };

          systemd.paths.cloudflared-tunnel-xnode = {
            wantedBy = [ "paths.target" ];
            pathConfig = {
              PathExists = "${data}/.cloudflared/tunnel.json";
              Unit = "cloudflared-tunnel-xnode.service";
            };
          };
          systemd.services.cloudflared-tunnel-xnode = {
            wantedBy = lib.mkForce [ ];
            serviceConfig.User = lib.mkForce "xnode-reverse-proxy";
            serviceConfig.Group = lib.mkForce "xnode-reverse-proxy";
            serviceConfig.DynamicUser = lib.mkForce false;
          };
          services.cloudflared = {
            enable = true;
            tunnels."xnode" = {
              credentialsFile = "${data}/.cloudflared/tunnel.json";
              default = "https://127.0.0.1"; # Forward to NGINX
              originRequest.noTLSVerify = true; # Allow self-signed certificates
            };
          };
        })
      ]
    );
}
