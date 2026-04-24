{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.xnode;
  owner =
    if (builtins.pathExists "${cfg.xnode-config}/owner") then
      builtins.readFile "${cfg.xnode-config}/owner"
    else
      "";
  domain =
    if (builtins.pathExists "${cfg.xnode-config}/domain") then
      builtins.readFile "${cfg.xnode-config}/domain"
    else
      "";
  email =
    if (builtins.pathExists "${cfg.xnode-config}/email") then
      builtins.readFile "${cfg.xnode-config}/email"
    else
      "";
in
{
  imports = [
    inputs.self.nixosModules.dns
    inputs.self.nixosModules.reverse-proxy
    inputs.xnode-manager.nixosModules.default
    inputs.xnode-auth.nixosModules.default
  ];

  config = {
    security.acme = {
      acceptTerms = true;
      defaults.email = if (email != "") then email else "xnode@openmesh.network";
    };
    systemd.services."acme-order-renew-manager.xnode.local".script =
      lib.mkForce ''echo "selfsigned only"'';

    services.xnode-manager = {
      enable = true;
      buildBase =
        (lib.nixosSystem {
          inherit pkgs;
          modules = [
            (
              { pkgs, ... }@args:
              {
                imports = [ inputs.self.nixosModules.app ];

                config = {
                  xnode = {
                    xnode-config = pkgs.emptyDirectory;
                    container.enable = args.lib.mkForce true;
                    auto-update.enable = args.lib.mkForce false;
                    pin-state-version.enable = args.lib.mkForce false;
                  };
                  system.stateVersion = args.config.system.nixos.release;
                };
              }
            )
          ];
        }).config.system.build.toplevel.outPath;
    };

    services.xnode-dns = {
      enable = true;
      soa.nameserver = if (domain != "") then domain else "xnode.local";
    };

    services.xnode-reverse-proxy = {
      enable = true;
      https = builtins.listToAttrs (
        builtins.map
          (domain: {
            name = domain;
            value."/".locations = [
              { socket = config.services.xnode-manager.socket; }
            ];
          })
          (
            [ "manager.xnode.local" ]
            ++ (lib.optionals (domain != "" && domain != "xnode.local") [ "manager.${domain}" ])
          )
      );
    };

    services.xnode-auth = {
      enable = true;
      domains = lib.mkIf (owner != "") (
        builtins.listToAttrs (
          builtins.map
            (domain: {
              name = domain;
              value = {
                accessList = {
                  users = {
                    "${owner}" = {
                      roles = [ "owner" ];
                    };
                  };
                  roles = {
                    "owner" = { };
                  };
                };
              };
            })
            (
              [ "manager.xnode.local" ]
              ++ (lib.optionals (domain != "" && domain != "xnode.local") [ "manager.${domain}" ])
            )
        )
      );
    };
  };
}
