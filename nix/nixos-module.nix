{ inputs }:
{
  lib,
  ...
}:
{
  imports = [
    ./os/base.nix
    (import ./os/hardware.nix { inherit inputs; })
    (import ./os/disks.nix { inherit inputs; })
    ./os/encrypted.nix
    ./os/network.nix
    ./os/state-version.nix
    (import ./os/manager.nix { inherit inputs; })
    ./os/password.nix
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
