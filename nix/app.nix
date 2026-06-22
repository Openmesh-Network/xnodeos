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
    ./xnode-info.nix
    ./xnode-secret.nix

    inputs.self.nixosModules.dns
    inputs.self.nixosModules.reverse-proxy
    inputs.xnode-auth.nixosModules.default

    ./container.nix
  ];

  config = {
    xnode.container.enable = type == "container";

    xnode.root = "/";

    boot.initrd.systemd.enable = true;
    nixpkgs.hostPlatform =
      if (builtins.pathExists "${cfg.xnode-config}/host-platform") then
        builtins.readFile "${cfg.xnode-config}/host-platform"
      else
        "x86_64-linux";

    xnode.manager.cache = [
      {
        location = "https://openmesh.cachix.org";
        public-keys = [ "du4NDeMWxcX8T5GddfuD0s/Tosl3+6b+T2+CLKHgXvQ=" ];
      }
    ];
  };
}
