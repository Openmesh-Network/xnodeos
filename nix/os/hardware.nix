{ config, ... }:
let
  cfg = config.xnode;
in
{
  config = {
    hardware.facter.reportPath = "${cfg.xnode-config}/hardware"; # Import extra modules based on detected hardware
  };
}
