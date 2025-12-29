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
          text = lib.concatStrings [
            ''
              boot_json=/nix/var/nix/profiles/system/boot.json
              kernel=$(jq -r '."org.nixos.bootspec.v1".kernel' "$boot_json")
              initrd=$(jq -r '."org.nixos.bootspec.v1".initrd' "$boot_json")
              init=$(jq -r '."org.nixos.bootspec.v1".init' "$boot_json")
              kernelParams=$(jq -r '."org.nixos.bootspec.v1".kernelParams | join(" ")' "$boot_json")
            ''
            ''
              dir=$(mktemp -d)
              ukify build \
                --linux="$kernel" \
                --initrd="$initrd" \
                --cmdline="init=$init $kernelParams" \
                --os-release @${config.environment.etc."os-release".source} \
                --output="$dir/uki.efi"
            ''
            ''
              sbctl sign "$dir/uki.efi"
            ''
            ''
              esp=${config.boot.loader.efi.efiSysMountPoint}
              rm -rf "''${esp:?}/*"
              mkdir -p "$esp/EFI/BOOT"
              mv "$dir/uki.efi" "$esp/EFI/BOOT/BOOT${lib.toUpper config.nixpkgs.hostPlatform.efiArch}.EFI"
              rm -rf "$dir"
            ''
            (
              if (tpm == "2") then
                ''
                  SYSTEMD_ESP_PATH="$esp" ${config.systemd.package}/lib/systemd/systemd-pcrlock make-policy --pcr=7
                ''
              else
                ''''
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
