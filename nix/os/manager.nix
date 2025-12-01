{ inputs }:
{ config, lib, ... }:
let
  owner =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/owner") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/owner"
    else
      "";
  domain =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/domain") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/domain"
    else
      "";
  email =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/email") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/email"
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
    services.xnode-manager = {
      enable = true;
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = if (email != "") then email else "xnode@openmesh.network";
    };
    security.acme.defaults.extraLegoRenewFlags = [ "--ari-disable" ]; # ARI causes issues currently, re-enable once more stable

    services.xnode-dns = {
      enable = true;
      soa.nameserver = if (domain != "") then domain else "manager.xnode.local";
    };

    systemd.services."acme-manager.xnode.local".script = lib.mkForce ''echo "selfsigned only"'';
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
              accessList."${owner}" = { };
            };
          }) ([ "manager.xnode.local" ] ++ (lib.optionals (domain != "") [ domain ]))
        )
      );
    };
  };
}
