{ inputs }:
{ config, lib, ... }:
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
    ../dns-module.nix
    ../reverse-proxy-module.nix
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

    services.xnode-manager.enable = true;

    services.xnode-dns = {
      enable = true;
      soa.nameserver = if (domain != "") then domain else "manager.xnode.local";
    };

    services.xnode-reverse-proxy = {
      enable = true;
      rules = builtins.listToAttrs (
        builtins.map (domain: {
          name = domain;
          value = [
            { forward = "http://unix:${config.services.xnode-manager.socket}"; }
          ];
        }) ([ "manager.xnode.local" ] ++ (lib.optionals (domain != "") [ domain ]))
      );
    };

    services.xnode-auth = {
      enable = true;
      domains = lib.mkIf (owner != "") (
        builtins.listToAttrs (
          builtins.map (domain: {
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
          }) ([ "manager.xnode.local" ] ++ (lib.optionals (domain != "") [ domain ]))
        )
      );
    };
  };
}
