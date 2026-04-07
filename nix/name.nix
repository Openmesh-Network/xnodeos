{ config, lib, ... }:
let
  cfg = config.xnode;
in
{
  config = {
    networking.hostName = lib.mkIf (builtins.pathExists "${cfg.xnode-config}/name") (
      builtins.readFile "${cfg.xnode-config}/name"
    );
  };
}
