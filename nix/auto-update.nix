{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.xnode.auto-update;
in
{
  options = {
    xnode.auto-update = {
      enable = lib.mkEnableOption "automated system updates";

      package = {
        nix = lib.mkPackageOption pkgs "nix" { } // {
          default = config.nix.package;
        };

        systemd = lib.mkPackageOption pkgs "systemd" { } // {
          default = config.systemd.package;
        };

        coreutils = lib.mkPackageOption pkgs "coreutils" { };
      };

      root = lib.mkOption {
        type = lib.types.str;
        default = config.xnode.root;
        example = "/";
        description = ''
          Root folder to put result in, the NixOS configuration should be in subfolder ./config.
        '';
      };

      reboot = lib.mkOption {
        type = lib.types.enum [
          "auto"
          "never"
          "always"
        ];
        default = "auto";
        example = "never";
        description = ''
          Reboot policy after updates. Auto will do a best effort prediction to decide if a reboot is required.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.timers.auto-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedOffsetSec = "24h";
        Persistent = true;
      };
    };

    systemd.services.auto-update = {
      description = "Update, rebuild, and apply this NixOS system.";
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
      };
      script =
        let
          nix = lib.getExe cfg.package.nix;
          mv = lib.getExe' cfg.package.coreutils "mv";
          systemctl = lib.getExe' cfg.package.systemd "systemctl";
        in
        ''
          ${nix} flake update --flake "${cfg.root}/config"

          ${nix} build "${cfg.root}/config#nixosConfigurations.xnode.config.system.build.toplevel" --out-link "${cfg.root}/new-result"

          REBOOT=${if cfg.reboot == "always" then "true" else "false"}

          ${mv} "${cfg.root}/new-result" "${cfg.root}/result" --no-target-directory

          "${cfg.root}/result/bin/switch-to-configuration" switch

          if [[ $REBOOT == true ]]; then
            ${systemctl} reboot
          fi
        '';
    };
  };
}
