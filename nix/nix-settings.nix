{ ... }:
{
  config = {
    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        flake-registry = "";
        accept-flake-config = true;
      };

      optimise.automatic = true;
      channel.enable = false;

      gc = {
        automatic = true;
        dates = "daily";
      };

      daemonCPUSchedPolicy = "idle";
      daemonIOSchedClass = "idle";
    };

    systemd.timers.nix-gc.timerConfig.RandomizedOffsetSec = "24h";
  };
}
