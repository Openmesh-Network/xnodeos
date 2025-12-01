{ inputs }:
{ config, lib, ... }:
let
  disks = builtins.split "\n" (builtins.readFile "${config.services.xnodeos.xnode-config}/disks");
  encrypted =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/encrypted") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/encrypted"
    else
      "";
  email =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/email") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/email"
    else
      "";
in
{
  imports = [
    inputs.disko.nixosModules.default
  ];

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
              boot = {
                size = "1M";
                type = "EF02"; # for MBR
              };
              ESP = {
                size = "1G";
                type = "EF00";
                content = {
                  type = "mdraid";
                  name = "boot";
                };
              };
            }
            // (
              if (encrypted == "1") then
                {
                  luks = {
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
                }
              else
                {
                  root = {
                    size = "100%";
                  };
                }
            );
          };
        };
      }) disks
    );
    mdadm = {
      boot = {
        type = "mdadm";
        level = 1;
        metadata = "1.0";
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          mountOptions = [ "umask=0077" ];
        };
      };
    };
  };

  boot.swraid.mdadmConf = ''
    MAILADDR ${email}
  '';
}
