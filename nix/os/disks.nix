{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.xnode;
  disks = lib.splitString "\n" (builtins.readFile "${cfg.xnode-config}/disks");
  tpm =
    if (builtins.pathExists "${cfg.xnode-config}/tpm") then
      builtins.readFile "${cfg.xnode-config}/tpm"
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
        path = "${cfg.xnode-config}/disk-key";
      };
    })
    {
      services.btrfs.autoScrub = {
        enable = true;
        fileSystems = [ "/" ];
      };

      systemd.services.esp-sync = {
        wantedBy = [ "multi-user.target" ];
        description = "Sync /boot to all ESPs";
        unitConfig.X-StopOnReconfiguration = true;
        serviceConfig = {
          Type = "notify";
          NotifyAccess = "all";
        };
        path = [
          pkgs.inotify-tools
          config.systemd.package
          pkgs.util-linux
          pkgs.rsync
        ];
        script = ''
          inotifywait --monitor --recursive --event close_write,create,delete,moved_to,moved_from /boot/ 2> >( 
            # Wait for readiness message
            while read line; do
              echo "$line" >&2
              if [ "$line" = "Watches established." ]; then
                systemd-notify --ready
              fi
            done
          ) | while read line; do 
            if [ -z "$debounce" ]; then
              debounce=1
              echo "TRIGGER: $line"
              (
                sleep 0.01
                debounce=
                ${lib.readFile ./scripts/esp-sync.sh}
              ) &
            else
              echo "DEBOUNCED: $line"
            fi
          done
        '';
      };
    }
  ];
}
