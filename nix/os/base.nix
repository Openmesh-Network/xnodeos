{ config, pkgs, ... }:
{
  config = {
    users.mutableUsers = false; # Prevent non-declarative users
    users.allowNoPasswordLogin = true; # Allow a system without any users that can be logged into

    zramSwap.enable = true; # Compress memory
    services.fwupd.enable = true; # Allow applications to update firmware
    services.dbus.implementation = "broker"; # High performance and reliability implementation of D-Bus

    # Change greeting to XnodeOS + ip address
    services.getty.greetingLine = ''
      <<< Welcome to Openmesh XnodeOS ${config.system.nixos.label} (\m) - \l >>>
      Access remotely through: \4 \6
    '';

    # Update limits
    boot.kernel.sysctl = {
      "fs.inotify.max_user_instances" = 2147483647;
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.neigh.default.gc_thresh1" = 4096;
      "net.ipv4.neigh.default.gc_thresh2" = 8192;
      "net.ipv4.neigh.default.gc_thresh3" = 16384;
    };
    systemd.services.nginx.serviceConfig.LimitNOFILE = 65536;
    systemd.services.dbus-broker.serviceConfig.LimitNOFILE = 65536;

    systemd.package =
      let
        kernelDev = config.system.build.kernel.dev;
        vmlinuxH = pkgs.runCommand "vmlinux.h" { } ''
          mkdir -p $out
          ${pkgs.bpftools}/bin/bpftool btf dump file ${kernelDev}/vmlinux format c > $out/vmlinux.h
        '';
      in
      pkgs.systemdUkify.overrideAttrs (old: {
        mesonFlags = old.mesonFlags ++ [
          "-Dvmlinux-h=provided"
          "-Dvmlinux-h-path=${vmlinuxH}/vmlinux.h"
        ];
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.bpftools ];
      });

    systemd.additionalUpstreamSystemUnits = [
      "systemd-nsresourced.service"
      "systemd-nsresourced.socket"
      "systemd-mountfsd.service"
      "systemd-mountfsd.socket"
    ];
    systemd.services.systemd-nsresourced.wantedBy = [ "multi-user.target" ];
    systemd.sockets.systemd-nsresourced.wantedBy = [ "sockets.target" ];
    systemd.services.systemd-mountfsd.wantedBy = [ "multi-user.target" ];
    systemd.sockets.systemd-mountfsd.wantedBy = [ "sockets.target" ];
  };
}
