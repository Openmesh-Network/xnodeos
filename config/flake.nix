{
  description = "XnodeOS Configuration";

  inputs = {
    xnodeos.url = "github:Openmesh-Network/xnodeos";
    nixpkgs.follows = "xnodeos/nixpkgs";
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

  outputs =
    { nixpkgs, ... }@inputs:
    {
      nixosConfigurations.xnode = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          inputs.xnodeos.nixosModules.default
          {
            services.xnodeos.xnode-config = ./xnode-config;
          }
          (
            { pkgs, ... }@args:
            {
              # START USER CONFIG

              # END USER CONFIG
            }
          )
        ];
      };
    };
}
