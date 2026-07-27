# https://github.com/joleuger/vuinputd/blob/main/docs/USAGE-NIXOS.md
{
  config,
  pkgs,
  lib,
  ...
}:
let
  vuinputd = pkgs.rustPlatform.buildRustPackage {
    pname = "vuinputd";
    version = "git-09052026";
    buildType = "debug";

    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.rustPlatform.bindgenHook
    ];

    buildInputs = [
      pkgs.udev
      pkgs.fuse3
    ];

    src = pkgs.fetchFromGitHub {
      owner = "joleuger";
      repo = "vuinputd";
      rev = "b9b4d1a07b3d56041208ffdfee884d195e7cbd51";
      hash = "sha256-eatTqd7A8ZQ7+CeEgGE8J7OAILCXshgq1GUm/Byeeok=";
    };

    cargoHash = "sha256-5+A73HyCgyFy2gHpCbZV+Tlx5rUpUkLGVPxYvDEwVmc=";

    # Recent versions of fuse3 expose additional libfuse_* types that bindgen
    # needs to allowlist alongside the standard fuse_* types.
    postPatch = ''
      substituteInPlace cuse-lowlevel/build.rs \
        --replace-fail '.allowlist_type("(?i)^fuse.*")' '.allowlist_type("(?i)^(fuse|libfuse).*")'
    '';

    postInstall = ''
      mkdir -p $out/lib/udev/rules.d
      mkdir $out/lib/udev/hwdb.d
      cp vuinputd/udev/*.rules $out/lib/udev/rules.d/
      cp vuinputd/udev/*.hwdb $out/lib/udev/hwdb.d/
    '';
  };
  cfg = config.xnode;
  debug =
    if (builtins.pathExists "${cfg.xnode-config}/debug") then
      builtins.readFile "${cfg.xnode-config}/debug"
    else
      "";
in
lib.mkIf (debug != "") {
  # https://github.com/girl-pp-ua/nixos-infra/blob/master/modules/services/experimental/gayming-nixos/uinput-vuinputd.nix
  security.wrappers.vuinputd = {
    owner = "root";
    group = "root";
    capabilities = "cap_sys_admin,cap_mknod,cap_dac_override,cap_fowner+eip";
    source = lib.getExe vuinputd;
  };
  services.udev.packages = [ vuinputd ];
  systemd.services.vuinputd = {
    description = "Virtual input (/dev/vuinput) daemon";
    after = [ "systemd-udevd.service" ];
    requires = [ "systemd-udevd.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      RUST_LOG = "debug";
    };
    serviceConfig = {
      Type = "exec";
      ExecStartPre = pkgs.writeShellScript "mount-tmpfs-dev-input" ''
        mkdir -p /run/vuinputd/vuinput/dev-input
        ${lib.getExe pkgs.mount} -t tmpfs -o rw,dev,nosuid tpmfs /run/vuinputd/vuinput/dev-input
      '';
      ExecStart = "${config.security.wrapperDir}/vuinputd --major 120 --minor 414795  --placement on-host";
      ExecStopPost = pkgs.writeShellScript "umount-dev-input" ''
        ${lib.getExe pkgs.umount} /run/vuinputd/vuinput/dev-input
      '';
      Restart = "on-failure";
      DeviceAllow = "char-* rwm";
    };
  };
}
