{
  config,
  lib,
  ...
}:
let
  cfg = config.xnode.info;
in
{
  options = {
    xnode.info = {
      enable = lib.mkEnableOption "Xnode Info" // {
        default = true;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.xnode-info = { };
    users.users.xnode-info = {
      isSystemUser = true;
      group = "xnode-info";
    };

    systemd.tmpfiles.rules = [
      "d /xnode-info 0775 xnode-info xnode-info -"
      "d /xnode-info/dns 0775 xnode-info xnode-info -" # Request certain DNS records to be set
      "d /xnode-info/auth 0775 xnode-info xnode-info -" # Expose Xnode Auth Users to share access to
    ];
  };
}
