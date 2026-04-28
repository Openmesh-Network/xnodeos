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
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
      };
      environment = {
        "NIX_REMOTE" = "daemon";
      };
      script =
        let
          nix = lib.getExe cfg.package.nix;
          systemctl = lib.getExe' cfg.package.systemd "systemctl";
          readlink = lib.getExe' pkgs.coreutils "readlink";
        in
        ''
          ${nix} flake update --flake "${cfg.root}/config"

          ${nix} build "${cfg.root}/config#nixosConfigurations.xnode.config.system.build.toplevel" --out-link "${cfg.root}/new-result"

          ${
            if cfg.reboot == "always" then
              "REBOOT=true"
            else if cfg.reboot == "never" then
              "REBOOT=false"
            else
              # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/tasks/auto-upgrade.nix
              ''
                booted="$(${readlink} /run/booted-system/{initrd,kernel,kernel-modules})"
                built="$(${readlink} /new-result/{initrd,kernel,kernel-modules})"
                if [ "$booted" = "$built" ]; then
                  REBOOT=false
                else
                  REBOOT=true
                fi
              ''
          }

          if [[ $REBOOT == true ]]; then
            "${cfg.root}/new-result/bin/switch-to-configuration" boot
            ${systemctl} reboot
          else
            "${cfg.root}/new-result/bin/switch-to-configuration" switch
          fi
        '';
    };
  };
}
