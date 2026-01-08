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
          ++ lib.optionals (boot == "BIOS") [ pkgs.gptfdisk ];
          text = lib.concatStrings [
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
            ''
              mkdir -p "$esp/EFI/BOOT"
              mv "$tmp/uki.efi" "$esp/EFI/BOOT/BOOT${lib.toUpper config.nixpkgs.hostPlatform.efiArch}.EFI"
            ''

            # Emulate UEFI on BIOS to allow UKI booting
            # https://github.com/NixOS/nixpkgs/issues/124132
            # https://wiki.archlinux.org/title/Clover#chainload_systemd-boot
            (lib.optionalString (boot == "BIOS") ''
              clover=${
                let
                  version = "5165";
                in
                pkgs.fetchzip {
                  name = "clover-${version}";
                  url = "https://github.com/CloverHackyColor/CloverBootloader/releases/download/${version}/CloverV2-${version}.zip";
                  sha256 = "sha256-KbaSQMJWNkBwdFKbYALCTfw0XcL5Cnfb2uIDzLdiLI0=";
                }
              }
              boot0=$clover/BootSectors/boot0af
              boot1=$clover/BootSectors/boot1f32
              boot2=$clover/Bootloaders/x64/boot7
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

                dd if="$boot0" of="$disk" bs=1 count=440 conv=notrunc

                cp "$boot1" "$tmp/new_PBR"
                dd if="$part" of="$tmp/original_PBR" bs=512 count=1 conv=notrunc
                dd if="$tmp/original_PBR" of="$tmp/new_PBR" skip=3 seek=3 bs=1 count=87 conv=notrunc
                dd if="$tmp/new_PBR" of="$part" bs=512 count=1 conv=notrunc
                rm "$tmp/new_PBR" "$tmp/original_PBR"
              done

              cp $boot2 "$esp/boot"
              mkdir -p "$esp/EFI"
              cp -a "$clover/EFI/CLOVER" "$esp/EFI/CLOVER"
              cat << EOF > "$esp/EFI/CLOVER/config.plist"
              <?xml version="1.0" encoding="UTF-8"?>
              <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
              <plist version="1.0">
              <dict>
                <key>Boot</key>
                <dict>
                  <key>DefaultVolume</key>
                  <string>EFI</string>
                  <key>DefaultLoader</key>
                  <string>\EFI\BOOT\BOOT${lib.toUpper config.nixpkgs.hostPlatform.efiArch}.EFI</string>
                  <key>Fast</key>
                  <true/>
                </dict>
                <key>GUI</key>
                <dict>
                  <key>Custom</key>
                  <dict>
                    <key>Entries</key>
                    <array>
                      <dict>
                        <key>Hidden</key>
                        <false/>
                        <key>Disabled</key>
                        <false/>
                        <key>Volume</key>
                        <string>EFI</string>
                        <key>Path</key>
                        <string>\EFI\BOOT\BOOT${lib.toUpper config.nixpkgs.hostPlatform.efiArch}.EFI</string>
                        <key>Title</key>
                        <string>XnodeOS</string>
                        <key>Type</key>
                        <string>Linux</string>
                      </dict>
                    </array>
                  </dict>
                </dict>
              </dict>
              </plist>
              EOF
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
