{ lib, config, ... }:
let
  encrypted =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/encrypted") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/encrypted"
    else
      "";
in
{
  config = lib.mkMerge [
    (lib.mkIf (encrypted == "1") {
      # Secure Boot
      boot.loader.limine.secureBoot.enable = true;

      # Full Disk Encryption
      # Decrypt all LUKS devices unattended with Clevis (TPM2)
      boot.initrd.availableKernelModules = [
        "tpm_crb"
        "tpm_tis"
        "virtio-pci"
      ];
      boot.initrd.clevis.enable = true;
      boot.initrd.clevis.devices = lib.mapAttrs (name: disk: {
        secretFile = "${config.services.xnodeos.xnode-config}/encryption-key";
      }) config.disko.devices.disk;
    })
    (lib.mkIf (encrypted == "") {
      # Include plain text file to decrypt all LUKS devices unattended
      # This is not secure; it allows a physical attacker to retrieve this key and decrypt the disks
      boot.initrd.luks.devices = lib.mapAttrs (name: disk: {
        keyFile = "/tmp/secret.key";
      }) config.disko.devices.disk;

      boot.initrd.secrets."/tmp/secret.key" = builtins.path {
        path = "${config.services.xnodeos.xnode-config}/encryption-key";
      };
    })
  ];
}
