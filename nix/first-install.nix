{ config, pkgs, ... }:
{
  config = {
    system.build.first-install = pkgs.writeShellScript "first-install" ''
      toplevel="__TOPLEVEL__"
      "$toplevel/activate" || echo "Failed to activate"
      "$toplevel/sw/bin/systemd-tmpfiles" --create --remove -E || echo "Failed to setup tmpfiles"
      NIXOS_INSTALL_BOOTLOADER=1 "$toplevel/bin/switch-to-configuration" boot
    '';

    system.systemBuilderCommands = ''
      substitute ${config.system.build.first-install} $out/first-install \
        --replace __TOPLEVEL__ $out
      chmod +x $out/first-install
    '';
  };
}
