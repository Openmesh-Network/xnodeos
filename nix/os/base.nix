{ ... }:
{
  config = {
    boot.loader.limine = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      maxGenerations = 1;
    };

    boot.loader.timeout = 0; # Speed up boot by skipping selection
    boot.enableContainers = true; # Enable nixos containers
    services.fwupd.enable = true; # Allow applications to update firmware
    zramSwap.enable = true; # Compress memory
    services.dbus.implementation = "broker"; # high performance and reliability implementation of D-Bus

    # Default limit easily exhausted
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

    boot.supportedFilesystems = [ "btrfs" ];
    fileSystems."/" = {
      device = "/dev/disk/by-label/ROOT";
      fsType = "btrfs";
    };

    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        flake-registry = "";
        accept-flake-config = true;
      };
      optimise.automatic = true;
      channel.enable = false;

      gc = {
        automatic = true;
        dates = "daily";
        randomizedDelaySec = "24h";
        options = "--delete-old";
      };
    };

    users.mutableUsers = false;
    users.allowNoPasswordLogin = true;

    networking = {
      hostName = "xnode";
      useDHCP = false;
      useNetworkd = true;
      wireless.iwd = {
        enable = true;
      };
    };

    systemd.network = {
      enable = true;
      wait-online = {
        timeout = 10;
        anyInterface = true;
      };
      networks = {
        "99-wired" = {
          matchConfig.Name = "en*";
          networkConfig = {
            DHCP = "yes";
          };
          dhcpV4Config.RouteMetric = 100;
          dhcpV6Config.WithoutRA = "solicit";
        };
        "99-wireless" = {
          matchConfig.Name = "wl*";
          networkConfig = {
            DHCP = "yes";
          };
          dhcpV4Config.RouteMetric = 200;
          dhcpV6Config.WithoutRA = "solicit";
        };
      };
    };
  };
}
