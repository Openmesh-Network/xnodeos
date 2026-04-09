{
  lib,
  ...
}:
{
  options = {
    xnode = {
      xnode-config = lib.mkOption {
        type = lib.types.path;
        example = ./xnode-config;
        description = ''
          Folder with configuration files.
        '';
      };

      root = lib.mkOption {
        type = lib.types.str;
        example = "/";
        description = ''
          The NixOS configuration should be in subfolder ./config.
        '';
      };
    };
  };
}
