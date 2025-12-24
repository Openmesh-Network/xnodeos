{ inputs }:
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    services.getty.greetingLine = ''<<< Welcome to Openmesh XnodeOS Installer ${config.system.nixos.label} (\m) - \l >>>'';
    services.getty.autologinUser = lib.mkForce "root";
    users.users.root.shell = lib.getExe (
      pkgs.writeShellScriptBin "install-xnodeos-progress" ''
        ${config.systemd.package}/bin/journalctl -u install-xnodeos.service -f
      ''
    );

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

    boot.initrd.systemd.enable = true;
    environment.etc."pcrlock.d".source = "${pkgs.systemd}/lib/pcrlock.d";

    services.resolved.enable = true;
    zramSwap.enable = true;
    services.dbus.implementation = "broker";
    boot.swraid = {
      enable = true;
      mdadmConf = ''
        MAILADDR samuel.mens@openmesh.network
      '';
    };

    systemd.services.install-xnodeos = {
      wantedBy = [ "multi-user.target" ];
      description = "Install XnodeOS.";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 1;
      };
      path =
        let
          # Wrap executable in bin folder to use it in path
          systemd-pcrlock = pkgs.stdenv.mkDerivation {
            name = "systemd-pcrlock";
            buildCommand = ''
              mkdir -p $out/bin
              ln -s ${config.systemd.package}/lib/systemd/systemd-pcrlock $out/bin/systemd-pcrlock
            '';
          };
        in
        [
          pkgs.util-linuxMinimal
          pkgs.jq
          pkgs.curl
          pkgs.nix
          pkgs.disko
          pkgs.nixos-facter
          pkgs.sbctl
          config.systemd.package
          systemd-pcrlock

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
  };
}
