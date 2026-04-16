{
  config,
  ...
}:
let
  cfg = config.xnode;
  type =
    if (builtins.pathExists "${cfg.xnode-config}/type") then
      builtins.readFile "${cfg.xnode-config}/type"
    else
      "";
in
{
  imports = [
    ./xnode-config.nix
    ./container-module.nix
  ];

  config = {
    xnode.container.enable = type == "container";
  };
}
