{
  config,
  lib,
  ...
}:
let
  cfg = config.xnode.secret;
in
{
  options = {
    xnode.secret = {
      enable = lib.mkEnableOption "Xnode Secret" // {
        default = true;
      };

      input = lib.mkOption {
        type = lib.types.str;
        default = "${config.xnode.xnode-config}/secret";
        example = "/config/xnode-config/secret";
        description = ''
          Directory to read the encrypted files from.
        '';
      };

      output = lib.mkOption {
        type = lib.types.str;
        default = "/run/secrets";
        example = "/run/xnode-secret";
        description = ''
          Directory to write the decrypted files to.
        '';
      };

      values = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        readOnly = true;
        default = lib.optionalAttrs (builtins.pathExists cfg.input) (
          lib.mapAttrs (name: type: "${cfg.output}/${name}") (builtins.readDir cfg.input)
        );
        description = ''
          Get path of secret by file name.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L467
    systemd.services.xnode-secret = {
      description = "Decrypt Xnode Secrets to ${cfg.output}";
      wantedBy = [ "sysinit.target" ];
      after = [
        "systemd-tpm2-setup.service"
        "local-fs.target"
        "systemd-sysusers.service"
        "userborn.service"
      ];
      requiredBy = [ "sysinit-reactivation.target" ];
      before = [ "sysinit-reactivation.target" ];
      unitConfig = {
        ConditionPathExists = cfg.input;
        DefaultDependencies = "no";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = lib.mkIf (lib.hasPrefix "/run/" cfg.output) (
          lib.removePrefix "/run/" cfg.output
        );
        RuntimeDirectoryMode = "0700";
      };
      script = ''
        for file in "${cfg.input}"/*; do
          [ -e "$file" ] || continue
          name=$(basename "$file")
          systemd-creds decrypt "$file" "${cfg.output}/$name"
        done
      '';
    };
  };
}
