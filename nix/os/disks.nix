{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  disks = lib.splitString "\n" (builtins.readFile "${config.services.xnodeos.xnode-config}/disks");
  tpm =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/tpm") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/tpm"
    else
      "";
in
{
  imports = [
    inputs.disko.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      fileSystems = {
        "/" = {
          label = "ROOT";
          fsType = "btrfs";
          options = [
            "lazytime"
            "noatime"
            "compress-force=zstd:1"
            "subvol=root"
          ];
        };
        "/nix" = {
          label = "ROOT";
          fsType = "btrfs";
          options = [
            "lazytime"
            "noatime"
            "compress-force=zstd:1"
            "subvol=nix"
          ];
        };
        "/boot" = {
          label = "ROOT";
          fsType = "btrfs";
          options = [
            "lazytime"
            "noatime"
            "compress-force=zstd:1"
            "subvol=boot"
          ];
        };
      };
    }
    {
      disko.devices = {
        disk = builtins.listToAttrs (
          lib.lists.imap0 (index: disk: {
            name = "disk${builtins.toString index}";
            value = {
              device = "/dev/${disk}";
              type = "disk";
              content = {
                type = "gpt";
                partitions = {
                  ESP = {
                    size = "1G";
                    type = "EF00";
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      extraArgs = [
                        "-n"
                        "EFI"
                      ];
                      mountpoint = "/boot${builtins.toString index}";
                      mountOptions = [
                        "umask=0077"
                      ];
                    };
                  };
                  LUKS = {
                    size = "100%";
                    content = {
                      type = "luks";
                      name = "disk${builtins.toString index}";
                      passwordFile = "/tmp/secret.key";
                      settings = {
                        allowDiscards = true;
                        bypassWorkqueues = true;
                      };
                    };
                  };
                };
              };
            };
          }) disks
        );
      };
    }
    (lib.mkIf (tpm == "2") {
      # Attempt unattended unlock using TPM2
      boot.initrd.luks.devices = lib.mapAttrs (name: disk: {
        crypttabExtraOpts = [
          "tpm2-device=auto"
        ];
      }) config.disko.devices.disk;
    })
    (lib.mkIf (tpm != "2") {
      # Include plain text file to decrypt all LUKS devices unattended
      # This is not secure; it allows a physical attacker to retrieve this key and decrypt the disks
      boot.initrd.luks.devices = lib.mapAttrs (name: disk: {
        keyFile = "/tmp/secret.key";
      }) config.disko.devices.disk;

      boot.initrd.secrets."/tmp/secret.key" = builtins.path {
        path = "${config.services.xnodeos.xnode-config}/disk-key";
      };
    })
    {
      services.btrfs.autoScrub = {
        enable = true;
        fileSystems = [ "/" ];
      };

      systemd.paths.esp-sync = {
        wantedBy = [ "multi-user.target" ];
        description = "Watch for /boot changes";
        pathConfig = {
          PathModified = "/boot/";
        };
      };

      systemd.services.esp-sync = {
        description = "Sync /boot to all ESPs";
        serviceConfig = {
          KillMode = "none";
        };
        path = [
          pkgs.util-linux
          pkgs.rsync
        ];
        script = ''
          for target in /boot*; do
            [ "$target" = "/boot" ] && continue

            if mountpoint -q "$target"; then
              echo "Syncing /boot -> $target"
              rsync -a --delete --inplace /boot/ "$target/" 2>&1 || echo "Syncing to $target failed"
            else
              echo "Skipping $target (not mounted)"
            fi
          done
        '';
      };
    }
  ];
}
