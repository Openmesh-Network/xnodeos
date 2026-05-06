{ inputs }:
{
  config,
  ...
}:
let
  cfg = config.xnode;
  type =
    if (builtins.pathExists "${cfg.xnode-config}/type") then
      builtins.readFile "${cfg.xnode-config}/type"
    else
      "";
in
{
  imports = [
    ./first-install.nix
    ./xnode-config.nix
    ./nix-settings.nix
    ./manager.nix
    ./state-version.nix
    ./name.nix
    ./auto-update.nix
    ./yggdrasil.nix

    inputs.self.nixosModules.dns
    inputs.self.nixosModules.reverse-proxy
    inputs.xnode-auth.nixosModules.default

    ./container.nix
  ];

  config = {
    xnode.container.enable = type == "container";

    xnode = {
      root = "/";
      auto-update.enable = true;
      pin-state-version.enable = true;
    };

    services.xnode-yggdrasil.enable = true;
    services.xnode-dns.enable = true;
    services.xnode-reverse-proxy.enable = true;
    services.xnode-auth.enable = true;

    boot.initrd.systemd.enable = true;
    nixpkgs.hostPlatform =
      if (builtins.pathExists "${cfg.xnode-config}/host-platform") then
        builtins.readFile "${cfg.xnode-config}/host-platform"
      else
        "x86_64-linux";
  };
}
