## XnodeOS

The operating system that powers all Xnodes.

## XnodeOS Install

> [!CAUTION]
> THIS WILL OVERWRITE THE CURRENTLY INSTALLED OS AND ALL ITS DATA, INCLUDING ANY ATTACHED DRIVES!

NixOS installation with custom XnodeOS configuration replacing an existing OS installation (e.g Ubuntu 24.04). Performs steps based on https://nixos.org/manual/nixos/stable/index.html#sec-installing-from-other-distro. This command should be run as root (`sudo su`).

OWNER env var should be set when deploying in a open-port environment to prevent malicious actors from claiming your Xnode before you.
DOMAIN env var should be set to communicate with xnode-manager over HTTPS without proxy. DOMAIN (can be a subdomain) should have an A record point to this Xnode. EMAIL env var should be set in case you own this domain, it can not be a blacklisted email (e.g. @example.com).

DEBUG env var can be set to any password that can be used to login as user "xnode". This is for debugging purposes only, it is recommended to manage your machine through [xnode-manager](https://github.com/Openmesh-Network/xnode-manager) only.

INITIAL_CONFIG env var can be set to apply any user configuration to the initial system, such as additional configuration required to access xnode-manager.

VERSION env var can be set to use a specific version installer instead of latest.

The installer will fully encrypt all writable non-removable drives (with unattended TPM2 decryption on boot, if TPM2 is detected). For Secure Boot keys to be automatically enrolled, Secure Boot should be enabled and the system should be booted into setup mode before running the installer. This protects against malicious actors with physical access to your Xnode.

The kexec installer will attempt to copy the statically configured networking configuration of the currently running operating system, but might not work for more exotic setups. Network configuration through DHCP is recommended.

```
curl -L https://opnm.sh/install | bash 2>&1
```

### Cloud Init

```
#cloud-config
runcmd:
 - |
   export DOMAIN="xnode.plopmenz.com" && export EMAIL="plopmenz@gmail.com" && export OWNER="eth:519ce4c129a981b2cbb4c3990b1391da24e8ebf3" && curl https://raw.githubusercontent.com/Openmesh-Network/xnodeos/main/install.sh | bash 2>&1 | tee /tmp/xnodeos.log
```
