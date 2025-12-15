{ inputs }:
{ config, ... }:
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  config = {
    boot.loader.timeout = 0;
    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
      configurationLimit = 1;
    };
  };
}
