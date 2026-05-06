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
    ./yggdrasil.nix
  ];

  config = {
    xnode = {
      root = "/var/lib/xnode-manager/host";
      auto-update.enable = true;
      pin-state-version.enable = true;
    };

    services.xnode-yggdrasil.enable = true;
    services.xnode-yggdrasil.proxy.enable = true;
    services.yggdrasil.settings.Peers = [ "tls://peer.yggdrasil.openmesh.cloud:9003" ];

    services.xnode-dns.enable = true;
    services.xnode-reverse-proxy.enable = true;
    services.xnode-auth.enable = true;
  };
}
