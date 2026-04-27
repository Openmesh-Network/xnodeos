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
    ./manager-module.nix
    ./state-version.nix
    ./name.nix
    ./auto-update.nix

    ./container-module.nix
  ];

  config = {
    xnode.container.enable = type == "container";

    xnode = {
      root = "/";
      auto-update.enable = true;
      pin-state-version.enable = true;
    };

    boot.initrd.systemd.enable = true;
    nixpkgs.hostPlatform =
      if (builtins.pathExists "${cfg.xnode-config}/host-platform") then
        builtins.readFile "${cfg.xnode-config}/host-platform"
      else
        "x86_64-linux";
  };
}
