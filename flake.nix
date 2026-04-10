{
  description = "XnodeOS Modules";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    xnode-manager = {
      url = "github:Openmesh-Network/xnode-manager/WIP";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xnode-auth = {
      url = "github:Openmesh-Network/xnode-auth/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
      default = import ./nix/nixos-module.nix { inherit inputs; };
      app = ./nix/app-module.nix;
      container = ./nix/container-module.nix;
      dns = ./nix/dns-module.nix;
      reverse-proxy = ./nix/reverse-proxy-module.nix;
    };
  };
}
