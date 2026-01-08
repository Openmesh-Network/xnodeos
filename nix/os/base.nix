{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    boot.enableContainers = true; # Enable nixos containers
    users.mutableUsers = false; # Prevent non-declarative users
    users.allowNoPasswordLogin = true; # Allow a system without any users that can be logged into
    services.getty.greetingLine = ''<<< Welcome to Openmesh XnodeOS ${config.system.nixos.label} (\m) - \l >>>''; # Change greeting to specify XnodeOS
    zramSwap.enable = true; # Compress memory
    services.fwupd.enable = true; # Allow applications to update firmware
    services.dbus.implementation = "broker"; # High performance and reliability implementation of D-Bus

    # Update limits
    boot.kernel.sysctl = {
      "fs.inotify.max_user_instances" = 2147483647;
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.neigh.default.gc_thresh1" = 4096;
      "net.ipv4.neigh.default.gc_thresh2" = 8192;
      "net.ipv4.neigh.default.gc_thresh3" = 16384;
    };
    systemd.services.nginx.serviceConfig.LimitNOFILE = 65536;
    systemd.services.dbus-broker.serviceConfig.LimitNOFILE = 65536;

    # Nix config
    nix =
      let
        flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
      in
      {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          flake-registry = "";
          accept-flake-config = true;
          nix-path = config.nix.nixPath;
        };
        registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
        nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;

        optimise.automatic = true;
        channel.enable = false;

        gc = {
          automatic = true;
          dates = "daily";
          randomizedDelaySec = "24h";
          options = "--delete-old";
        };
      };
  };
}
