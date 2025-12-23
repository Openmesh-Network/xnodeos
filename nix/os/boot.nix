{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    boot.loader.supportsInitrdSecrets = true;

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
    boot.loader.external = {
      enable = true;
      installHook = "${lib.getExe (
        pkgs.writeShellApplication {
          name = "install-uki";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.sbctl
            config.systemd.package
            pkgs.binutils
          ];
          text = ''
            boot_json=/nix/var/nix/profiles/system/boot.json
            kernel=$(jq -r '."org.nixos.bootspec.v1".kernel' "$boot_json")
            initrd=$(jq -r '."org.nixos.bootspec.v1".initrd' "$boot_json")
            init=$(jq -r '."org.nixos.bootspec.v1".init' "$boot_json")
            kernelParams=$(jq -r '."org.nixos.bootspec.v1".kernelParams | join(" ")' "$boot_json")

            dir=$(mktemp -d)
            ukify build \
              --linux="$kernel" \
              --initrd="$initrd" \
              --cmdline="init=$init $kernelParams" \
              --output="$dir/uki.efi"

            sbctl sign "$dir/uki.efi"

            esp=${config.boot.loader.efi.efiSysMountPoint}
            rm -rf "''${esp:?}/*"
            mkdir -p "$esp/EFI/BOOT"
            mv "$dir/uki.efi" "$esp/EFI/BOOT/BOOTX64.EFI"
            rm -rf "$dir"

            ${config.systemd.package}/lib/systemd/systemd-pcrlock lock-uki "$esp/EFI/BOOT/BOOTX64.EFI" --pcrlock="/var/lib/pcrlock.d/650-uki-new.pcrlock.d/generated.pcrlock"
            SYSTEMD_ESP_PATH="$esp" ${config.systemd.package}/lib/systemd/systemd-pcrlock make-policy --pcr=7 --pcr=11
          '';
        }
      )}";
    };

    systemd.services.pcrlock-make-policy = {
      wantedBy = [ "multi-user.target" ];
      description = "systemd-pcrlock make-policy";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if [ -f "/var/lib/pcrlock.d/650-uki-new.pcrlock.d/generated.pcrlock" ]; then
          rm -rf "/var/lib/pcrlock.d/650-uki-current.pcrlock.d/"
          mv "/var/lib/pcrlock.d/650-uki-new.pcrlock.d/" "/var/lib/pcrlock.d/650-uki-current.pcrlock.d/"
          SYSTEMD_ESP_PATH="${config.boot.loader.efi.efiSysMountPoint}" ${config.systemd.package}/lib/systemd/systemd-pcrlock make-policy --pcr=7 --pcr=11
        fi
      '';
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
