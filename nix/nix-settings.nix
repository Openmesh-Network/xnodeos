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
        keep-outputs = true; # Significantly speed up updates at the cost of more disk usage
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
