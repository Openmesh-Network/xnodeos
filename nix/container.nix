{
  config,
  options,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.xnode;
in
{
  options = {
    xnode.container = {
      enable = lib.mkEnableOption "run system in container";
    };
  };

  config = lib.mkIf cfg.container.enable {
    system.boot.loader.id = "xnode-boot-container";
    boot = lib.mkMerge [
      (
        if builtins.hasAttr "isNspawnContainer" options.boot then
          { isNspawnContainer = true; }
        else
          { isContainer = true; }
      )
      {
        loader.external = {
          enable = true;
          installHook = "${lib.getExe (
            pkgs.writeShellApplication {
              name = "xnode-boot-container";
              runtimeInputs = [
                pkgs.coreutils
              ];
              text =
                let
                  root = config.xnode.root;
                in
                ''
                  toplevel="$1"
                  mkdir -p /sbin
                  cp "$toplevel/init" /sbin/init
                  mv "${root}/new-result" "${root}/result" --no-target-directory
                '';
            }
          )}";
        };
      }
      {
        kernel.sysctl = {
          "net.ipv4.ping_group_range" = "0 65535";
        };
      }
    ];

    # https://github.com/NixOS/nixpkgs/issues/405256
    systemd.services.nix-daemon.serviceConfig.ExecStart = [
      ""
      "${lib.getExe' pkgs.util-linux "unshare"} -m ${pkgs.writeShellScript "start-nix-daemon" ''
        ${lib.getExe' pkgs.util-linux "mount"} -t proc proc /proc
        exec -a nix-daemon ${lib.getExe' config.nix.package.out "nix-daemon"} --daemon
      ''}"
    ];

    networking = {
      useDHCP = false;
      useNetworkd = true;
      nftables.enable = true;
      firewall.allowedUDPPorts = [ 5355 ];
    };
    systemd.network = {
      enable = true;
      wait-online = {
        timeout = 10;
        anyInterface = true;
      };
      networks = {
        "80-container-host0" = {
          matchConfig = {
            Kind = "veth";
            Name = "host0";
            Virtualization = "container";
          };
          networkConfig = {
            DHCP = "yes";
            LinkLocalAddressing = "yes";
            LLDP = "yes";
            EmitLLDP = "customer-bridge";
          };
          dhcpV4Config.UseDNS = false;
          dhcpV6Config.UseDNS = false;
        };
      };
    };

    networking.useHostResolvConf = false;
    services.resolved.enable = true;
  };
}
