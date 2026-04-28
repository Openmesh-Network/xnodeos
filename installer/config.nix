{ inputs }:
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    nixpkgs.overlays = [
      (final: prev: {
        nixos-facter = prev.nixos-facter.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace pkg/udev/udev.go \
              --replace 'return nil, fmt.Errorf("failed to parse bus: %w", err)' \
                        '/* Unknown bus (e.g. "acpi"), ignore instead of failing */'
          '';
        });
      })
    ];

    system.nixos.distroName = "Openmesh XnodeOS Installer";
    services.getty.extraArgs = [
      "--issue-file=/etc/issue"
    ];
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

    boot.initrd.systemd.enable = true;
    environment.etc."pcrlock.d".source = "${config.systemd.package}/lib/pcrlock.d";
    environment.etc."xnodeos-config-cache".source =
      inputs.config.nixosConfigurations.xnode.config.system.build.toplevel;
    environment.etc."xnodeos-config-file".text = builtins.readFile ../config/flake.nix;
    environment.etc."xnodeos-config-lock".text = builtins.readFile ../config/flake.lock;

    services.resolved.enable = true;
    zramSwap.enable = true;
    services.dbus.implementation = "broker";

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
        RestartSec = 10;
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
          pkgs.util-linux
          pkgs.jq
          pkgs.curl
          pkgs.nix
          pkgs.disko
          pkgs.nixos-facter
          pkgs.sbctl
          config.systemd.package
          systemd-pcrlock

          # Disko dependencies

          # build
          pkgs.dieHook
          pkgs.gcc
          pkgs.libgcc
          pkgs.gmp
          pkgs.isl
          pkgs.libmpc
          pkgs.makeBinaryWrapper
          pkgs.mpfr
          pkgs.stdenvNoCC

          # destroy
          # pkgs.util-linux
          pkgs.e2fsprogs
          pkgs.mdadm
          pkgs.zfs
          pkgs.lvm2
          pkgs.bash
          # pkgs.jq
          pkgs.gnused
          pkgs.gawk
          pkgs.coreutils-full

          # create
          pkgs.gnugrep
          # pkgs.bash
          pkgs.gptfdisk
          pkgs.parted
          pkgs.dosfstools
          pkgs.cryptsetup
          pkgs.btrfs-progs
        ];
      script = lib.readFile ./install.sh;
    };

    system.stateVersion = config.system.nixos.release;

    # Reduce closure size (https://github.com/nix-community/nixos-images/blob/main/nix/noninteractive.nix)
    system.extraDependencies = lib.mkForce [ ];
    system.disableInstallerTools = true;
    programs.nano.enable = false;
    security.sudo.enable = false;

    # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/minimal.nix
    documentation = {
      enable = lib.mkDefault false;
      doc.enable = lib.mkDefault false;
      info.enable = lib.mkDefault false;
      man.enable = lib.mkDefault false;
      nixos.enable = lib.mkDefault false;
    };

    environment = {
      # Perl is a default package.
      defaultPackages = lib.mkDefault [ ];
      stub-ld.enable = lib.mkDefault false;
    };

    programs = {
      command-not-found.enable = lib.mkForce false;
      fish.generateCompletions = lib.mkDefault false;
    };

    services = {
      logrotate.enable = lib.mkDefault false;
      udisks2.enable = lib.mkDefault false;
    };

    xdg = {
      autostart.enable = lib.mkDefault false;
      icons.enable = lib.mkDefault false;
      mime.enable = lib.mkDefault false;
      sounds.enable = lib.mkDefault false;
    };
  };
}
