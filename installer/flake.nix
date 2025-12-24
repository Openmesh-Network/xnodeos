{
  description = "XnodeOS Installer";

  inputs = {
    config.url = "path:../config";
    nixpkgs.follows = "config/nixpkgs";
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
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          kexec = (pkgs.nixos [ self.nixosModules.kexec ]).config.system.build.kexecInstallerTarball;
          iso = (pkgs.nixos [ self.nixosModules.iso ]).config.system.build.isoImage;
        }
      );
      nixosModules = {
        kexec = import ./kexec.nix { inherit inputs; };
        iso = import ./iso.nix { inherit inputs; };
      };
    };
}
