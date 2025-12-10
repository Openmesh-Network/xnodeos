{ inputs }:
{ config, ... }:
{
  imports = [
    inputs.nixos-facter-modules.nixosModules.facter
  ];

  config.facter.reportPath = "${config.services.xnodeos.xnode-config}/hardware"; # Import extra modules based on detected hardware
}
