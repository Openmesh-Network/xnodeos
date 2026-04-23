{ config, ... }:
let
  cfg = config.xnode;
  name =
    if (builtins.pathExists "${cfg.xnode-config}/name") then
      builtins.readFile "${cfg.xnode-config}/name"
    else
      "xnode";
in
{
  config = {
    networking.hostName = name;
  };
}
