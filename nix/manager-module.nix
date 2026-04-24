{
  config,
  lib,
  ...
}:
let
  location = lib.mkOption {
    type = lib.types.oneOf [
      (lib.types.addCheck (lib.types.submodule {
        options = {
          port = lib.mkOption {
            type = lib.types.port;
            example = 80;
            description = ''
              What port to reach this location on.
            '';
          };
        };
      }) (x: x ? port))

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
    ];
    description = ''
      How to reach the location.
    '';
  };
  http = lib.types.attrsOf (
    lib.types.submodule {
      options = {
        inherit location;
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
  );
in
{
  options = {
    xnode.manager = {
      cache = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              location = lib.mkOption {
                type = lib.types.str;
                example = "https://openmesh.cachix.org";
                description = ''
                  Where the cache is located.
                '';
              };

              public-keys = lib.mkOption {
                type = lib.types.str;
                example = [ "du4NDeMWxcX8T5GddfuD0s/Tosl3+6b+T2+CLKHgXvQ=" ];
                description = ''
                  What public keys are required to have signed files to download them from this cache. 
                '';
              };

              description = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Additional information for the user.
                '';
              };
            };
          }
        );
        default = [ ];
        example = [
          {
            location = "https://nix-community.cachix.org";
            public-keys = [ "mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
          }
        ];
        description = ''
          Recommended caches for xnode-manager to use.
        '';
      };

      permission = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options =
              let
                weight = lib.types.enum [
                  "Idle"
                  (lib.types.submodule {
                    options = {
                      Value = lib.mkOption {
                        type = lib.types.int;
                      };
                    };
                  })
                ];
              in
              {
                process = lib.mkOption {
                  type = lib.types.nullOr (
                    lib.types.submodule {
                      options = {
                        cpu = {
                          weight = lib.mkOption {
                            type = lib.types.nullOr weight;
                            default = null;
                            description = ''
                              In case there is more work than compute power, in what relative priority to allocate compute to this process. (default 100)
                            '';
                          };

                          max = lib.mkOption {
                            type = lib.types.nullOr lib.types.int;
                            default = null;
                            description = ''
                              Maximum compute power this process is allowed to use. (e.g. 100 is one core, 250 is two and a half cores)
                            '';
                          };

                          allowed_cores = lib.mkOption {
                            type = lib.types.nullOr (lib.types.listOf lib.types.int);
                            default = null;
                            description = ''
                              Specific core indexes, the process will only run on these cores.
                            '';
                          };
                        };

                        memory = {
                          max = lib.mkOption {
                            type = lib.types.nullOr lib.types.int;
                            default = null;
                            description = ''
                              Hard limit on memory this process is allowed to use in bytes.
                            '';
                          };

                          soft_max = lib.mkOption {
                            type = lib.types.nullOr lib.types.int;
                            default = null;
                            description = ''
                              Memory usage may go above the limit if unavoidable, but the processes are heavily slowed down and memory is taken away aggressively in such cases.
                            '';
                          };
                        };

                        subprocess = {
                          max = lib.mkOption {
                            type = lib.types.nullOr lib.types.int;
                            default = null;
                            description = ''
                              Maximum number of subprocesses this process is allowed to spawn.
                            '';
                          };
                        };

                        io = lib.mkOption {
                          type = lib.types.nullOr (
                            lib.types.attrsOf (
                              lib.types.submodule {
                                options = {
                                  weight = lib.mkOption {
                                    type = lib.types.nullOr weight;
                                    default = null;
                                    description = ''
                                      In case there is more work than IO, in what relative priority to allocate IO to this process. (default 100)
                                    '';
                                  };

                                  max_bandwidth = lib.mkOption {
                                    type = lib.types.nullOr (
                                      lib.types.submodule {
                                        options = {
                                          read = lib.mkOption {
                                            type = lib.types.nullOr lib.types.int;
                                            default = null;
                                          };

                                          write = lib.mkOption {
                                            type = lib.types.nullOr lib.types.int;
                                            default = null;
                                          };
                                        };
                                      }
                                    );
                                    default = null;
                                    description = ''
                                      Maximum block IO bandwidth this process is allowed to use in bytes.
                                    '';
                                  };

                                  max_iops = lib.mkOption {
                                    type = lib.types.nullOr (
                                      lib.types.submodule {
                                        options = {
                                          read = lib.mkOption {
                                            type = lib.types.nullOr lib.types.int;
                                            default = null;
                                          };

                                          write = lib.mkOption {
                                            type = lib.types.nullOr lib.types.int;
                                            default = null;
                                          };
                                        };
                                      }
                                    );
                                    default = null;
                                    description = ''
                                      Maximum block IO IOs-per-Second this process is allowed to use.
                                    '';
                                  };
                                };
                              }
                            )
                          );
                          default = null;
                        };
                      };
                    }
                  );
                  default = null;
                };

                disk = lib.mkOption {
                  type = lib.types.nullOr (
                    lib.types.submodule {
                      options = {
                        total = lib.mkOption {
                          type = lib.types.nullOr lib.types.int;
                          default = null;
                        };
                      };
                    }
                  );
                  default = null;
                };

                bind = lib.mkOption {
                  type = lib.types.nullOr (
                    lib.types.attrsOf (
                      lib.types.submodule {
                        options = {
                          path = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                          };

                          readonly = lib.mkOption {
                            type = lib.types.nullOr lib.types.bool;
                            default = null;
                          };
                        };
                      }
                    )
                  );
                  default = null;
                };

                device = lib.mkOption {
                  type = lib.types.nullOr (
                    lib.types.submodule {
                      options = {
                        policy = lib.mkOption {
                          type = lib.types.nullOr lib.types.enum [
                            "Strict"
                            "Closed"
                            "Auto"
                          ];
                          default = null;
                        };

                        allow = lib.mkOption {
                          type = lib.types.nullOr (
                            lib.types.attrsOf (
                              lib.types.submodule {
                                options = {
                                  read = lib.mkOption {
                                    type = lib.types.nullOr lib.types.bool;
                                    default = null;
                                  };

                                  write = lib.mkOption {
                                    type = lib.types.nullOr lib.types.bool;
                                    default = null;
                                  };

                                  mknod = lib.mkOption {
                                    type = lib.types.nullOr lib.types.bool;
                                    default = null;
                                  };
                                };
                              }
                            )
                          );
                          default = null;
                        };
                      };
                    }
                  );
                  default = null;
                };

                extra_args = lib.mkOption {
                  type = lib.types.nullOr (lib.types.listOf lib.types.str);
                  default = null;
                };
              };
          }
        );
        default = { };
        example = {
          container = {
            process = {
              cpu = {
                weight = {
                  Value = 100;
                };
                max = 250;
                allowed_cores = [
                  0
                  1
                  2
                  3
                ];
              };
              memory = {
                max = 1000000000000;
                soft_max = 500000000000;
              };
              subprocess = {
                max = 4096;
              };
              io = {
                weight = 100;
                max_bandwidth = {
                  read = 1000000000;
                  write = 500000000;
                };
                max_iops = {
                  read = 1000000;
                  write = 1000000;
                };
              };
            };
            disk = {
              total = 10000000000000;
            };
            bind = {
              "/data" = {
                path = "/host/container/data";
                readonly = true;
              };
            };
            device = {
              policy = "closed";
              allow = {
                "/dev/dri" = {
                  read = true;
                  write = true;
                  mknod = false;
                };
              };
            };
            extra_args = [
              "--network-veth"
              "--private-users=managed"
              "--private-users-ownership=foreign"
              "--private-users-delegate=1"
            ];
          };
          virtual-machine = {
            extra_args = [
              "--network-tap"
            ];
          };
        };
        description = ''
          Recommended permissions for xnode-manager to grant.
        '';
      };

      expose = {
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = config.networking.hostName;
          example = "my-app";
          description = ''
            Recommended subdomain for xnode-manager to expose http(s) under.
          '';
        };

        http = lib.mkOption {
          type = http;
          default = { };
          example = {
            "/" = {
              protocol = "https";
              location = {
                port = 443;
              };
            };
            "/api" = {
              location = {
                socket = "/run/my-app/.socket";
              };
              path = "/";
            };
          };
          description = ''
            Recommended http(s) locations for xnode-manager to expose.
          '';
        };

        tcp = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                inherit location;
              };
            }
          );
          default = { };
          example = {
            "53".location = {
              port = 53;
            };
          };
          description = ''
            Recommended tcp locations for xnode-manager to expose.
          '';
        };

        udp = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                inherit location;
              };
            }
          );
          default = { };
          example = {
            "53".location = {
              port = 53;
            };
          };
          description = ''
            Recommended udp locations for xnode-manager to expose.
          '';
        };
      };

      ui = lib.mkOption {
        type = http;
        default = { };
        example = {
          config = {
            location = {
              port = 3000;
            };
          };
          dashboard = {
            location = {
              port = 3001;
            };
          };
          debug = {
            location = {
              socket = "/run/my-app/debug.socket";
            };
          };
        };
        description = ''
          Recommended user interfaces for xnode-manager to display.
        '';
      };
    };
  };
}
