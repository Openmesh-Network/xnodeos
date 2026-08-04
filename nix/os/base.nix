{ config, pkgs, ... }:
{
  config = {
    system.nixos.distroName = "XnodeOS";

    users.mutableUsers = false; # Prevent non-declarative users
    users.allowNoPasswordLogin = true; # Allow a system without any users that can be logged into

    zramSwap.enable = true; # Compress memory
    services.fwupd.enable = true; # Allow applications to update firmware

    services.getty.helpLine = ''Access Remotely: \4 \6 \6{ygg0}'';

    # Update limits
    boot.kernel.sysctl = {
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.core.default_qdisc" = "fq";
      "fs.inotify.max_user_instances" = 2147483647;
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.neigh.default.gc_thresh1" = 4096;
      "net.ipv4.neigh.default.gc_thresh2" = 8192;
      "net.ipv4.neigh.default.gc_thresh3" = 16384;
    };
    systemd.services.dbus-broker.serviceConfig.LimitNOFILE = 65536;

    powerManagement.cpuFreqGovernor = "performance";

    systemd.package =
      let
        kernelDev = config.system.build.kernel.dev;
        vmlinuxH = pkgs.runCommand "vmlinux.h" { } ''
          mkdir -p $out
          ${pkgs.bpftools}/bin/bpftool btf dump file ${kernelDev}/vmlinux format c > $out/vmlinux.h
        '';
      in
      (pkgs.systemd.override { withUkify = true; }).overrideAttrs (old: {
        # systemd-pcrlock
        postInstall = (old.postInstall or "") + ''
          ln -s $out/lib/systemd/systemd-pcrlock $out/bin/systemd-pcrlock
        '';
        # +BTF
        mesonFlags = (old.mesonFlags or [ ]) ++ [
          "-Dvmlinux-h=provided"
          "-Dvmlinux-h-path=${vmlinuxH}/vmlinux.h"
        ];
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.bpftools ];
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
