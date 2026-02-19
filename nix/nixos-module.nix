{ inputs }:
{
  lib,
  ...
}:
{
  imports = [
    (import ./os/base.nix { inherit inputs; })
    (import ./os/hardware.nix { inherit inputs; })
    (import ./os/boot.nix { inherit inputs; })
    (import ./os/disks.nix { inherit inputs; })
    ./os/network.nix
    ./os/state-version.nix
    (import ./os/manager.nix { inherit inputs; })
    ./os/minimal.nix
    ./os/debug.nix
  ];

  options = {
    services.xnodeos = {
      xnode-config = lib.mkOption {
        type = lib.types.path;
        example = ./xnode-config;
        description = ''
          Folder with configuration files.
        '';
      };
    };
  };
}
