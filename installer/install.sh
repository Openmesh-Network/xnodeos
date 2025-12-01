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

# Collect list of disks after formatting and mounting
OUTPUT_DISKS=()
for i in "${!DISKS[@]}"; do
  if [[ $ENCRYPTED ]]; then
    OUTPUT_DISKS+=("/dev/mapper/disk${i}")
  else
    if [[ $disk == nvme* || $disk == mmcblk* ]]; then
      OUTPUT_DISKS+=("/dev/${DISKS[$i]}p3")
    else
      OUTPUT_DISKS+=("/dev/${DISKS[$i]}3")
    fi
  fi
  DISK_COUNTER=$((DISK_COUNTER + 1))
done
# Save disk configuration
printf "%s\n" "${DISKS[@]}" > /etc/nixos/xnode-config/disks

if [[ $ENCRYPTED ]]; then
  # Generate disk encryption key
  echo -n "$(tr -dc '[:alnum:]' < /dev/random | head -c64)" > /tmp/secret.key

  # Encrypt disk password for unattended (TPM2) boot decryption (Clevis)
  # Initially do not bind to any pcrs (always allow decryption) for the first boot
  # Set pcrs after first boot (to capture the TPM2 register values of XnodeOS instead of XnodeOS installer)
  cat /tmp/secret.key | clevis encrypt tpm2 '{"pcr_ids": ""}' > /etc/nixos/xnode-config/clevis.jwe
fi

# Perform hardware scan
nixos-facter -o /etc/nixos/xnode-config/facter.json

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
if [[ $PASSWORD ]]; then
  echo -n "${PASSWORD}" > /etc/nixos/xnode-config/password
fi
if [[ $ENCRYPTED ]]; then
  echo -n "1" > /etc/nixos/xnode-config/encrypted
fi
if [[ $NETWORK ]]; then
  echo -n "${NETWORK}" > /etc/nixos/xnode-config/network
fi
if [[ $INITIAL_CONFIG ]]; then
  sed -i "/# START USER CONFIG/,/# END USER CONFIG/c\# START USER CONFIG\n${INITIAL_CONFIG}\n# END USER CONFIG" /etc/nixos/flake.nix
fi

# Apply disk formatting and mount drives
disko --mode destroy,format,mount --flake /etc/nixos --yes-wipe-all-disks
if [[ ${#OUTPUT_DISKS[@]} -gt 1 ]]; then
  # Multiple disks
  BRTFS_MODE="--data single --metadata raid1"
else
  # Single disk
  BRTFS_MODE="--data single --metadata dup"
fi
mkfs.btrfs --label ROOT ${BRTFS_MODE} ${OUTPUT_DISKS[@]}
mount /dev/disk/by-label/ROOT /mnt

# Move config to root file system
mkdir -p /mnt/etc/nixos
mv /etc/nixos /mnt/etc/nixos

if [[ $ENCRYPTED ]]; then
  # Generate Secure Boot Keys
  mkdir -p /mnt/var/lib/sbctl/keys
  sbctl create-keys --export /mnt/var/lib/sbctl/keys --database-path /mnt/var/lib/sbctl
fi

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
mount --rbind --mkdir / /mnt
mount --make-rslave /mnt
NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot
umount -R /mnt && (rmdir /mnt 2>/dev/null || true)
EOL
)"

# Boot into new OS
reboot