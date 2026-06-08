{
  description = "XnodeOS Modules";

  inputs = {
    disko.url = "github:nix-community/disko/latest";
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    lanzaboote.url = "github:nix-community/lanzaboote";

    xnode-manager.url = "github:Openmesh-Network/xnode-manager/v1";
    nixpkgs.follows = "xnode-manager/nixpkgs";

    xnode-auth.url = "github:Openmesh-Network/xnode-auth/v1";
  };

  nixConfig = {
    extra-substituters = [
      "https://openmesh.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "openmesh.cachix.org-1:du4NDeMWxcX8T5GddfuD0s/Tosl3+6b+T2+CLKHgXvQ="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs = inputs: {
    nixosModules = {
      default = inputs.xnode-manager.nixosModules.default;
      container = ./nix/container-module.nix;
      reverse-proxy = ./nix/reverse-proxy-module.nix;
    };
  };
}
