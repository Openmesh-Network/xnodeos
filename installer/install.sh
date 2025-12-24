# Create empty config folder
rm -rf /etc/nixos
mkdir -p /etc/nixos/xnode-config

# Collect all non-removable, writable disks
DISKS=()
mapfile -t DISKS < <(
  lsblk --nodeps --json |
    jq -r '.blockdevices[] | select(.type=="disk" and .rm==false and .ro==false) | .name' |
    grep -v '^zram' # Exclude zram
)

# Collect list of disks after formatting
OUTPUT_DISKS=()
for i in "${!DISKS[@]}"; do
  OUTPUT_DISKS+=("/dev/mapper/disk${i}")
done

# Save disk configuration
DISKSTR=$(printf "%s\n" "${DISKS[@]}")
echo -n "$DISKSTR" > /etc/nixos/xnode-config/disks

# Generate disk encryption key
echo -n "$(tr -dc '[:alnum:]' < /dev/random | head -c64)" > /tmp/secret.key

# Generate Secure Boot Keys
sbctl create-keys

# Attempt to enroll the Secure Boot Keys
# This will only work if setup mode was enabled before running the installer
sbctl enroll-keys || true

# Detect if system contains TPM
TPM=$(cat /sys/class/tpm/tpm0/tpm_version_major)
echo -n "${TPM}" > /etc/nixos/xnode-config/tpm

# Perform hardware scan
nixos-facter -o /etc/nixos/xnode-config/hardware

# Download main configuration
(curl -L "https://raw.githubusercontent.com/Openmesh-Network/xnodeos/main/config/flake.nix")> /etc/nixos/flake.nix

# Apply environmental variable configuration
if [[ $OWNER ]]; then
  echo -n "${OWNER}" > /etc/nixos/xnode-config/owner
fi
if [[ $DOMAIN ]]; then
  echo -n "${DOMAIN}" > /etc/nixos/xnode-config/domain
fi
if [[ $EMAIL ]]; then
  echo -n "${EMAIL}" > /etc/nixos/xnode-config/email
fi
if [[ $DEBUG ]]; then
  echo -n "${DEBUG}" > /etc/nixos/xnode-config/debug
fi
if [[ $NETWORK ]]; then
  echo -n "${NETWORK}" > /etc/nixos/xnode-config/network
fi
if [[ $INITIAL_CONFIG ]]; then
  sed -i "/# START USER CONFIG/,/# END USER CONFIG/c\# START USER CONFIG\n${INITIAL_CONFIG}\n# END USER CONFIG" /etc/nixos/flake.nix
fi

# Apply disk partitions and formatting
disko --mode destroy,format,mount --flake /etc/nixos#xnode --no-deps --yes-wipe-all-disks
if [[ ${#OUTPUT_DISKS[@]} -gt 1 ]]; then
  # Multiple disks
  BRTFS_MODE="--data single --metadata raid1"
else
  # Single disk
  BRTFS_MODE="--data single --metadata dup"
fi
mkfs.btrfs --force --label ROOT ${BRTFS_MODE} ${OUTPUT_DISKS[@]}
sleep 1 # /dev/disk/by-label/ROOT isn't available instantly

# Create subvolumes and mount disks 
mount --mkdir /dev/disk/by-label/ROOT /mnt
btrfs subvolume create /mnt/root
btrfs subvolume create /mnt/nix
umount /mnt
mount --mkdir -o lazytime,noatime,compress-force=zstd:1,subvol=root /dev/disk/by-label/ROOT /mnt
mount --mkdir -o lazytime,noatime,compress-force=zstd:1,subvol=nix /dev/disk/by-label/ROOT /mnt/nix
mount --mkdir -o umask=0077 /dev/md/BOOT /mnt/boot

if [[ $TPM == "2" ]]; then
  # Define policy of allowed TPM2 values
  systemd-pcrlock lock-secureboot-policy
  SYSTEMD_ESP_PATH=/mnt/boot systemd-pcrlock make-policy --pcr=7

  for i in "${!DISKS[@]}"; do
    # Setup unattended TPM2 boot decryption and remove password decryption
    systemd-cryptenroll --wipe-slot="all" --tpm2-device="auto" --unlock-key-file="/tmp/secret.key" "/dev/disk/by-partlabel/disk-disk${i}-LUKS"
  done
else
  # Store disk decryption key in plain text
  cp /tmp/secret.key /etc/nixos/xnode-config/disk-key
fi

# Symlink to disk
mkdir -p /mnt/etc
mkdir -p /mnt/var/lib

ln -s /etc/nixos /mnt/etc/nixos
ln -s /var/lib/sbctl /mnt/var/lib/sbctl
ln -s /var/lib/systemd /mnt/var/lib/systemd

# Copy over nix store contents
nix copy --to /mnt /run/current-system --no-check-sigs

# Build configuration
nix build /mnt/etc/nixos#nixosConfigurations.xnode.config.system.build.toplevel --store /mnt --profile /mnt/nix/var/nix/profiles/system

# Apply configuration
# Based on https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ni/nixos-install/nixos-install.sh and https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ni/nixos-enter/nixos-enter.sh
mkdir -p /mnt/dev /mnt/sys /mnt/proc
chmod 0755 /mnt/dev /mnt/sys /mnt/proc
mount --rbind /dev /mnt/dev
mount --rbind /sys /mnt/sys
mount --rbind /proc /mnt/proc
chroot /mnt /nix/var/nix/profiles/system/sw/bin/bash -c "$(cat << EOL
set -e
/nix/var/nix/profiles/system/activate || true
/nix/var/nix/profiles/system/sw/bin/systemd-tmpfiles --create --remove -E || true
/nix/var/nix/profiles/system/sw/bin/mount --rbind --mkdir / /mnt
/nix/var/nix/profiles/system/sw/bin/mount --make-rslave /mnt
NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot
/nix/var/nix/profiles/system/sw/bin/umount -R /mnt && (/nix/var/nix/profiles/system/sw/bin/rmdir /mnt 2>/dev/null || true)
EOL
)"

# Move symlink content
rm /mnt/etc/nixos
rm /mnt/var/lib/sbctl
rm /mnt/var/lib/systemd

cp /etc/nixos /mnt/etc
cp /etc/nixos /mnt/etc
cp /var/lib/sbctl /mnt/var/lib
cp /var/lib/systemd /mnt/var/lib

# Boot into new OS
reboot