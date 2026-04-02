# Create empty config folder
mkdir -p /var/lib/xnode-manager/host/config/xnode-config

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
echo -n "$DISKSTR" > /var/lib/xnode-manager/host/config/xnode-config/disks

# Generate disk encryption key
echo -n "$(tr -dc '[:alnum:]' < /dev/random | head -c64)" > /tmp/secret.key

# Generate Secure Boot Keys
sbctl create-keys

# Attempt to enroll the Secure Boot Keys
# This will only work if setup mode was enabled before running the installer
sbctl enroll-keys || true

# Detect if system contains TPM
TPM=$(cat /sys/class/tpm/tpm0/tpm_version_major) || TPM=""

# Detect if system is booted into UEFI or Legacy
[ -d /sys/firmware/efi ] && BOOT="UEFI" || BOOT="BIOS"

# Perform hardware scan
nixos-facter -o /var/lib/xnode-manager/host/config/xnode-config/hardware

# Set main configuration
cp /etc/xnodeos-config-file /var/lib/xnode-manager/host/config/flake.nix
cp /etc/xnodeos-config-lock /var/lib/xnode-manager/host/config/flake.lock
if [[ $VERSION == "latest" ]]; then
  # Remove version lock
  sed -i -e "s|\"github:Openmesh-Network/xnodeos/[^\"]*\"|\"github:Openmesh-Network/xnodeos\"|g" /var/lib/xnode-manager/host/config/flake.nix
fi

# Apply environmental variable configuration
if [[ $TPM ]]; then
  echo -n "${TPM}" > /var/lib/xnode-manager/host/config/xnode-config/tpm
fi
if [[ $BOOT ]]; then
  echo -n "${BOOT}" > /var/lib/xnode-manager/host/config/xnode-config/boot
fi
if [[ $OWNER ]]; then
  echo -n "${OWNER}" > /var/lib/xnode-manager/host/config/xnode-config/owner
fi
if [[ $DOMAIN ]]; then
  echo -n "${DOMAIN}" > /var/lib/xnode-manager/host/config/xnode-config/domain
fi
if [[ $EMAIL ]]; then
  echo -n "${EMAIL}" > /var/lib/xnode-manager/host/config/xnode-config/email
fi
if [[ $DEBUG ]]; then
  echo -n "${DEBUG}" > /var/lib/xnode-manager/host/config/xnode-config/debug
fi
if [[ $NETWORK ]]; then
  echo -n "${NETWORK}" > /var/lib/xnode-manager/host/config/xnode-config/network
fi
if [[ $INITIAL_CONFIG ]]; then
  sed -i "/# START USER CONFIG/,/# END USER CONFIG/c\# START USER CONFIG\n${INITIAL_CONFIG}\n# END USER CONFIG" /var/lib/xnode-manager/host/config/flake.nix
fi

# Apply disk partitions and formatting
disko --mode destroy,format,mount --flake /var/lib/xnode-manager/host/config#xnode --no-deps --yes-wipe-all-disks
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
btrfs subvolume create /mnt/boot
umount /mnt
mount --mkdir -o lazytime,noatime,compress-force=zstd:1,subvol=root /dev/disk/by-label/ROOT /mnt
mount --mkdir -o lazytime,noatime,compress-force=zstd:1,subvol=nix /dev/disk/by-label/ROOT /mnt/nix
mount --mkdir -o lazytime,noatime,compress-force=zstd:1,subvol=boot /dev/disk/by-label/ROOT /mnt/boot
for i in "${!DISKS[@]}"; do
  mount --mkdir -o umask=0077 "/dev/disk/by-partlabel/disk-disk${i}-ESP" "/mnt/boot${i}"
done
systemctl restart esp-sync.path

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
  cp /tmp/secret.key /var/lib/xnode-manager/host/config/xnode-config/disk-key
fi

# Copy content to disk
mkdir -p /mnt/var/lib
cp -r /var/lib/xnode-manager /mnt/var/lib
cp -r /var/lib/sbctl /mnt/var/lib
cp -r /var/lib/systemd /mnt/var/lib

# Build configuration
nix build /mnt/var/lib/xnode-manager/host/config#nixosConfigurations.xnode.config.system.build.toplevel --store /mnt --out-link /mnt/var/lib/xnode-manager/host/result --extra-substituters auto?trusted=1 --print-build-logs

# Apply configuration
systemd-run --pipe --root-directory /mnt /var/lib/xnode-manager/host/result/sw/bin/bash -c "$(cat << EOL
set -e
/var/lib/xnode-manager/host/result/activate || true
NIXOS_INSTALL_BOOTLOADER=1 /var/lib/xnode-manager/host/result/bin/switch-to-configuration boot
EOL
)"

# Boot into new OS
if [ -z "$DEBUG" ]; then
  reboot
fi