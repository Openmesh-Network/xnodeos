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

    systemd.paths.esp-sync = {
      wantedBy = [ "multi-user.target" ];
      description = "Watch for /mnt/boot changes";
      pathConfig = {
        PathModified = "/mnt/boot/";
      };
    };

    systemd.services.esp-sync = {
      description = "Sync /mnt/boot to all ESPs";
      serviceConfig = {
        KillMode = "none";
      };
      path = [
        pkgs.util-linux
        pkgs.rsync
      ];
      script = ''
        for target in /mnt/boot*; do
          [ "$target" = "/mnt/boot" ] && continue

          if mountpoint -q "$target"; then
            echo "Syncing /mnt/boot -> $target"
            rsync -a --delete --inplace /mnt/boot/ "$target/"
          else
            echo "Skipping $target (not mounted)"
          fi
        done
      '';
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
