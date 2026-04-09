{ inputs }:
{
  lib,
  ...
}:
{
  imports = [
    ./xnode-config.nix
    (import ./os/base.nix { inherit inputs; })
    (import ./os/hardware.nix { inherit inputs; })
    (import ./os/boot.nix { inherit inputs; })
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
