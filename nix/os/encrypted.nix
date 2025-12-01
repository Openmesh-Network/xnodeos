{ lib, config, ... }:
let
  encrypted =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/encrypted") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/encrypted"
    else
      "";
in
{
  config = lib.mkIf (encrypted == "1") {
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
    boot.initrd.clevis.devices = lib.mapAttrs (name: luksDevice: {
      secretFile = "${config.services.xnodeos.xnode-config}/clevis.jwe";
    }) config.boot.initrd.luks.devices;
  };
}
