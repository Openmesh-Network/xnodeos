{ inputs }:
{ config, lib, ... }:
let
  disks = builtins.split "\n" (builtins.readFile "${config.services.xnodeos.xnode-config}/disks");
  email =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/email") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/email"
    else
      "";
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
      boot.supportedFilesystems = [ "btrfs" ];
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
      };

      services.btrfs.autoScrub = {
        enable = true;
        fileSystems = [ "/" ];
      };

      disko.devices = {
        disk = builtins.listToAttrs (
          lib.lists.imap0 (index: value: {
            name = "disk${builtins.toString index}";
            value = {
              device = "/dev/${value}";
              type = "disk";
              content = {
                type = "gpt";
                partitions = {
                  BOOT = {
                    size = "1M";
                    type = "EF02"; # for MBR
                  };
                  ESP = {
                    size = "1G";
                    type = "EF00";
                    content = {
                      type = "mdraid";
                      name = "BOOT";
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
        mdadm = {
          BOOT = {
            type = "mdadm";
            level = 1;
            metadata = "1.0";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "umask=0077"
              ];
            };
          };
        };
      };

      boot.swraid.mdadmConf = ''
        MAILADDR ${email}
      '';
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
  ];
}
