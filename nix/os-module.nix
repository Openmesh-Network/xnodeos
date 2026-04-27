{ inputs }:
{
  lib,
  ...
}:
{
  imports = [
    ./first-install.nix
    ./xnode-config.nix
    ./nix-settings.nix
    ./os/base.nix
    ./os/hardware.nix
    ./os/boot.nix
    (import ./os/disks.nix { inherit inputs; })
    ./os/network.nix
    ./state-version.nix
    ./name.nix
    (import ./os/manager.nix { inherit inputs; })
    ./os/minimal.nix
    ./os/debug.nix
    ./auto-update.nix
  ];

  config = {
    xnode = {
      root = "/var/lib/xnode-manager/host";
      auto-update.enable = true;
      pin-state-version.enable = true;
    };
  };
}
