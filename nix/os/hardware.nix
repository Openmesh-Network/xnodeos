{ inputs }:
{ config, ... }:
let
  cfg = config.xnode;
in
{
  imports = [
    inputs.nixos-facter-modules.nixosModules.facter
  ];

  config.facter.reportPath = "${cfg.xnode-config}/hardware"; # Import extra modules based on detected hardware
}
