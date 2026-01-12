{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  tpm =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/tpm") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/tpm"
    else
      "";
  boot =
    if (builtins.pathExists "${config.services.xnodeos.xnode-config}/boot") then
      builtins.readFile "${config.services.xnodeos.xnode-config}/boot"
    else
      "";
in
{
  config = {
    boot.initrd.systemd.enable = true;
    boot.initrd.systemd.additionalUpstreamUnits = [ "systemd-pcrphase-initrd.service" ];
    boot.initrd.systemd.targets.initrd.wants = [ "systemd-pcrphase-initrd.service" ];
    boot.initrd.systemd.storePaths = [
      "${config.boot.initrd.systemd.package}/lib/systemd/systemd-pcrextend"
    ];
    systemd.additionalUpstreamSystemUnits = [
      "systemd-pcrextend@.service"
      "systemd-pcrextend.socket"
      "systemd-pcrphase.service"
      "systemd-pcrphase-sysinit.service"
    ];
    environment.etc."pcrlock.d".source = "${config.systemd.package}/lib/pcrlock.d";

    systemd.package = pkgs.systemdUkify;
    system.boot.loader.id = "uki";
    boot.loader.external = {
      enable = true;
      installHook = "${lib.getExe (
        pkgs.writeShellApplication {
          name = "install-uki";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.sbctl
            pkgs.systemdUkify
            pkgs.binutils
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
                boot_json=/nix/var/nix/profiles/system/boot.json
                kernel=$(jq -r '."org.nixos.bootspec.v1".kernel' "$boot_json")
                initrd=$(jq -r '."org.nixos.bootspec.v1".initrd' "$boot_json")
                init=$(jq -r '."org.nixos.bootspec.v1".init' "$boot_json")
                kernelParams=$(jq -r '."org.nixos.bootspec.v1".kernelParams | join(" ")' "$boot_json")

                esp=/boot
                tmp=$(mktemp -d)
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

              # Clean up ESP
              ''
                rm -rf "''${esp:?}/*"
              ''

              # Move UKI to ESP
              (lib.optionalString (boot == "UEFI") ''
                mkdir -p "$esp/EFI/BOOT"
                mv "$tmp/uki.efi" "$esp/EFI/BOOT/BOOT${arch}.EFI"
              '')

              # Emulate UEFI on BIOS to allow UKI booting
              # https://github.com/NixOS/nixpkgs/issues/124132
              # https://wiki.archlinux.org/title/Clover#chainload_systemd-boot
              (lib.optionalString (boot == "BIOS") ''
                oc=${
                  let
                    version = "1.0.6";
                  in
                  pkgs.fetchzip {
                    name = "open-core-${version}";
                    url = "https://github.com/acidanthera/OpenCorePkg/releases/download/${version}/OpenCore-${version}-RELEASE.zip";
                    sha256 = "sha256-+YcwRZ4mbbyh4Ivbk1bzLPFLlYtKUON0n+Co0+cp8c8=";
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
                mkdir -p "$esp/EFI"
                cp -a "$oc/${arch}/EFI/OC" "$esp/EFI/OC"
                cp -a "$oc/${arch}/EFI/BOOT" "$esp/EFI/BOOT"
                mv "$tmp/uki.efi" "$esp/EFI/xnodeos.efi"
                cp "$oc/Docs/Sample.plist" "$esp/EFI/OC/config.plist"

                # Disable Vault
                sed -i '/<key>Vault<\/key>/,/string>/ s/<string>Secure<\/string>/<string>Optional<\/string>/' "$esp/EFI/OC/config.plist"

                # Disable Secure Boot
                sed -i '/<key>SecureBootModel<\/key>/,/string>/ s/<string>Default<\/string>/<string>Disabled<\/string>/' "$esp/EFI/OC/config.plist"

                # Relax Scan Policy
                sed -i '/<key>ScanPolicy<\/key>/,/string>/ s/<integer>17760515<\/integer>/<integer>0<\/integer>/' "$esp/EFI/OC/config.plist"

                # Instantly Boot Into OS
                sed -i '/<key>ShowPicker<\/key>/,/string>/ s/<true\/>/<false\/>/' "$esp/EFI/OC/config.plist"

                # Remove Default Drivers
                sed -i '/<key>Drivers<\/key>/,/<\/array>/c\
                        <key>Drivers</key>\
                        <array/>' "$esp/EFI/OC/config.plist"

                # Remove Default Entries
                sed -i '/<key>Entries<\/key>/,/<\/array>/c\
                        <key>Entries</key>\
                        <array/>' "$esp/EFI/OC/config.plist"

                # Add XnodeOS Entry
                sed -i '/<key>BlessOverride<\/key>/,/<array\/>/c\
                    <key>BlessOverride</key>\
                    <array>\
                      <string>\\EFI\\xnodeos.efi</string>\
                    </array>' "$esp/EFI/OC/config.plist"
              '')

              # Update unattended disk decryption lock
              (lib.optionalString (tpm == "2") ''
                SYSTEMD_ESP_PATH="$esp" ${config.systemd.package}/lib/systemd/systemd-pcrlock make-policy --pcr=7
              '')

              # Remove temporary files
              ''
                rm -rf "$tmp"
              ''
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
