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
    (import ./state-version.nix { config-dir = "/var/lib/xnode-manager/host/config/xnode-config"; })
    (import ./os/manager.nix { inherit inputs; })
    ./os/minimal.nix
    ./os/debug.nix
  ];
}
