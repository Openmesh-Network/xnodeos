{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.xnode;
  boot =
    if (builtins.pathExists "${cfg.xnode-config}/boot") then
      builtins.readFile "${cfg.xnode-config}/boot"
    else
      "";
  update-pcr-lock = ''
    systemd-pcrlock lock-secureboot-policy || echo "Could not lock SecureBoot Policy"
    systemd-pcrlock lock-secureboot-authority || echo "Could not lock SecureBoot Authority"

    SYSTEMD_ESP_PATH="$esp" systemd-pcrlock make-policy --components="${config.systemd.package}/lib/pcrlock.d" --components=/var/lib/pcrlock.d --pcr=7 --pcr=11 ''${NIXOS_INSTALL_BOOTLOADER:+--force}
  '';
in
{
  config = {
    boot.initrd.systemd.enable = true;

    boot.kernelParams = [ "systemd.tpm2_software_fallback=yes" ];
    boot.initrd.systemd.additionalUpstreamUnits = [
      "systemd-tpm2-swtpm.service"
      "systemd-pcrosseparator.service"
    ];
    boot.initrd.systemd.services.systemd-tpm2-swtpm.path = [
      pkgs.swtpm
    ];
    boot.initrd.systemd.services.systemd-tpm2-swtpm.serviceConfig.ExecSearchPath = "${pkgs.swtpm}/bin";
    boot.initrd.systemd.storePaths = [
      "${config.systemd.package}/lib/systemd/systemd-tpm2-swtpm"
    ];
    boot.initrd.systemd.initrdBin = [ pkgs.swtpm ];
    boot.initrd.kernelModules = [ "tpm_vtpm_proxy" ];

    systemd.additionalUpstreamSystemUnits = [
      "systemd-tpm2-swtpm.service"
    ];
    systemd.services.systemd-tpm2-swtpm.environment."SYSTEMD_ESP_PATH" =
      "${config.boot.loader.efi.efiSysMountPoint}";
    systemd.services.systemd-tpm2-swtpm.path = [
      pkgs.swtpm
    ];
    systemd.services.systemd-tpm2-swtpm.serviceConfig.ExecSearchPath = "${pkgs.swtpm}/bin";
    system.fsPackages = [ pkgs.swtpm ];

    systemd.tpm2.pcrphases.enable = true;
    boot.initrd.systemd.tpm2.pcrphases.enable = true;
    boot.initrd.systemd.services.systemd-pcrosseparator.wantedBy = [ "initrd.target" ];

    systemd.services.current-uki-pcrlock = {
      wantedBy = [ "multi-user.target" ];
      description = "Update the uki current.pcrlock to the currently booted system.";
      wants = [ "esp-sync.service" ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        config.systemd.package
        pkgs.coreutils
      ];
      script = ''
        if [ -f /var/lib/pcrlock.d/650-uki.pcrlock.d/future.pcrlock ]; then
          mv /var/lib/pcrlock.d/650-uki.pcrlock.d/future.pcrlock /var/lib/pcrlock.d/650-uki.pcrlock.d/current.pcrlock
          esp="${config.boot.loader.efi.efiSysMountPoint}"
          ${update-pcr-lock}
        fi
      '';
    };

    system.boot.loader.id = "xnode-boot";
    boot.loader.external = {
      enable = true;
      installHook = "${lib.getExe (
        pkgs.writeShellApplication {
          name = "xnode-boot";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.sbctl
            config.systemd.package
            pkgs.binutils
            pkgs.util-linux
            pkgs.rsync
          ]
          ++ lib.optionals (boot == "BIOS") [
            pkgs.gptfdisk
            pkgs.gnused
          ];
          text =
            let
              arch = lib.toUpper config.nixpkgs.hostPlatform.efiArch;
            in
            lib.concatStrings [
              # Set environment
              ''
                toplevel="$1"
                boot_json="$toplevel/boot.json"
                kernel=$(jq -r '."org.nixos.bootspec.v1".kernel' "$boot_json")
                initrd=$(jq -r '."org.nixos.bootspec.v1".initrd' "$boot_json")
                init=$(jq -r '."org.nixos.bootspec.v1".init' "$boot_json")
                kernelParams=$(jq -r '."org.nixos.bootspec.v1".kernelParams | join(" ")' "$boot_json")

                esp="${config.boot.loader.efi.efiSysMountPoint}"
                tmp=$(mktemp -d)
              ''

              # Stop automatic ESP sync (will be done manually at end of installation)
              ''
                systemctl stop esp-sync.service || true
              ''

              # Build UKI
              ''
                ukify build \
                  --linux="$kernel" \
                  --initrd="$initrd" \
                  --cmdline="init=$init $kernelParams" \
                  --uname "${config.boot.kernelPackages.kernel.modDirVersion}" \
                  --os-release "@${config.system.build.etc}/etc/os-release" \
                  --output="$tmp/uki.efi"
              ''

              # Sign UKI
              ''
                sbctl sign "$tmp/uki.efi"
              ''

              # Update unattended disk decryption lock
              ''
                systemd-pcrlock lock-uki "$tmp/uki.efi" --pcrlock="/var/lib/pcrlock.d/650-uki.pcrlock.d/future.pcrlock"
                ${update-pcr-lock}
              ''

              # Move UKI to ESP
              (lib.optionalString (boot == "UEFI") ''
                mkdir -p "$esp/EFI/BOOT"
                mv "$tmp/uki.efi" "$esp/EFI/BOOT/BOOT${arch}.EFI"
              '')

              # Emulate UEFI on BIOS to allow UKI booting
              # https://github.com/NixOS/nixpkgs/issues/124132
              # https://wiki.archlinux.org/title/Clover#chainload_systemd-boot
              # https://github.com/acidanthera/OpenCorePkg/blob/master/Utilities/LegacyBoot/BootInstallBase.sh
              (lib.optionalString (boot == "BIOS") ''
                oc=${
                  let
                    version = "1.0.8";
                  in
                  pkgs.fetchzip {
                    name = "open-core-${version}";
                    url = "https://github.com/acidanthera/OpenCorePkg/releases/download/${version}/OpenCore-${version}-RELEASE.zip";
                    sha256 = "sha256-9vAO8SrJNofScQ3XjTe4oH3eMcwKx7viavsNjSJB2Iw=";
                    stripRoot = false;
                  }
                }
                boot0=$oc/Utilities/LegacyBoot/boot0
                boot1=$oc/Utilities/LegacyBoot/boot1f32
                boot2=$oc/Utilities/LegacyBoot/boot${arch}-blockio
                disks=(${
                  lib.concatStringsSep " " (map (disk: disk.device) (lib.attrValues config.disko.devices.disk))
                })

                for disk in "''${disks[@]}"; do
                  partition="1"
                  case "$disk" in
                    *nvme*|*mmcblk*)
                      part="''${disk}p''${partition}"
                      ;;
                    *)
                      part="''${disk}''${partition}"
                      ;;
                  esac

                  sgdisk --attributes="''${partition}:set:2" "$disk"

                  dd if="$boot0" of="$disk" bs=1 count=446 conv=notrunc

                  cp "$boot1" "$tmp/new_PBR"
                  dd if="$part" of="$tmp/original_PBR" count=1
                  dd if="$tmp/original_PBR" of="$tmp/new_PBR" skip=3 seek=3 bs=1 count=87 conv=notrunc
                  dd if=/dev/random of="$tmp/new_PBR" skip=496 seek=496 bs=1 count=14 conv=notrunc
                  dd if="$tmp/new_PBR" of="$part"
                  rm "$tmp/new_PBR" "$tmp/original_PBR"
                done

                cp $boot2 "$esp/boot"
                mkdir -p "$esp/EFI/OC"
                mv "$tmp/uki.efi" "$esp/EFI/OC/OpenCore.efi"
              '')

              # Sync to all ESPs
              ''
                ${lib.readFile ./scripts/esp-sync.sh}
              ''

              # Remove temporary files
              ''
                rm -rf "$tmp"
              ''

              # Update result symlink
              (
                let
                  root = config.xnode.root;
                in
                ''
                  mv "${root}/new-result" "${root}/result" --no-target-directory
                ''
              )
            ];
        }
      )}";
    };

    systemd.services.fwupd = {
      environment.FWUPD_EFIAPPDIR = "/run/fwupd-efi";
    };

    systemd.services.fwupd-efi = {
      description = "Sign fwupd EFI app for secure boot";
      wantedBy = [ "fwupd.service" ];
      partOf = [ "fwupd.service" ];
      before = [ "fwupd.service" ];

      unitConfig.ConditionPathIsDirectory = "/var/lib/sbctl";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "fwupd-efi";
      };

      script = ''
        cp ${config.services.fwupd.package.fwupd-efi}/libexec/fwupd/efi/fwupd*.efi /run/fwupd-efi/
        chmod +w /run/fwupd-efi/fwupd*.efi
        ${lib.getExe pkgs.sbctl} sign /run/fwupd-efi/fwupd*.efi
      '';
    };

    services.fwupd.uefiCapsuleSettings = {
      DisableShimForSecureBoot = true;
    };
  };
}
