{
  lib,
  ...
}:
{
  options = {
    xnode.xnode-config = lib.mkOption {
      type = lib.types.path;
      example = ./xnode-config;
      description = ''
        Folder with configuration files.
      '';
    };
  };
}
