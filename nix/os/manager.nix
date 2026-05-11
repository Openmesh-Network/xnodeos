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
in
{
  imports = [
    inputs.self.nixosModules.dns
    inputs.self.nixosModules.reverse-proxy
    inputs.xnode-manager.nixosModules.default
    inputs.xnode-auth.nixosModules.default
  ];

  config = {
    systemd.services."acme-order-renew-manager.xnode.local".script =
      lib.mkForce ''echo "selfsigned only"'';

    services.xnode-manager = {
      enable = true;
      buildBase = {
        container =
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
                      auto-update.enable = false;
                      pin-state-version.enable = false;
                    };
                    system.stateVersion = args.config.system.nixos.release;
                    nixpkgs.hostPlatform = args.lib.mkForce pkgs.stdenv.hostPlatform.system;
                  };
                }
              )
            ];
          }).config.system.build.toplevel.outPath;
      };
    };

    xnode.reverse-proxy.https = builtins.listToAttrs (
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

    services.xnode-auth.domains = lib.mkIf (owner != "") (
      builtins.listToAttrs (
        builtins.map
          (domain: {
            name = domain;
            value = {
              accessList = {
                users = {
                  ${owner} = {
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
}
