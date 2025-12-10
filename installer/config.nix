{ inputs }:
{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.getty.autologinUser = lib.mkForce "root";
  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        flake-registry = "";
        accept-flake-config = true;
        nix-path = config.nix.nixPath;
      };
      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
      channel.enable = false;
    };

  boot.loader.timeout = lib.mkForce 0;
  zramSwap.enable = true;
  services.dbus.implementation = "broker";

  boot.swraid = {
    enable = true;
    mdadmConf = ''
      MAILADDR samuel.mens@openmesh.network
    '';
  };
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];

  systemd.services.install-xnodeos = {
    wantedBy = [ "multi-user.target" ];
    description = "Install XnodeOS.";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      RemainAfterExit = true;
    };
    path = [
      pkgs.util-linuxMinimal
      pkgs.jq
      pkgs.curl
      pkgs.nix
      pkgs.disko
      pkgs.nixos-facter
      pkgs.sbctl
      pkgs.clevis
      # Disko dependencies
      pkgs.bash
      pkgs.gptfdisk
      pkgs.parted
      pkgs.dosfstools
      pkgs.mdadm
      pkgs.cryptsetup
      pkgs.btrfs-progs
    ];
    script = lib.readFile ./install.sh;
  };

  system.stateVersion = config.system.nixos.release;

  # Reduce closure size (https://github.com/nix-community/nixos-images/blob/main/nix/noninteractive.nix)
  environment.defaultPackages = lib.mkForce [ ];
  system.extraDependencies = lib.mkForce [ ];

  # Disable unused nixos tools
  system.disableInstallerTools = true;

  # Disable documentation
  documentation.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;
  documentation.doc.enable = false;

  # Disable unused programs
  programs.nano.enable = false;
  security.sudo.enable = false;
}
