# 02 — Host setup

Goal: at boot, the second GPU is claimed by `vfio-pci` instead of the graphics
driver, so libvirt can hand it to the VM.

Assumes [00 — Eligibility](00-eligibility.md) passed. Commands are for
Arch-based distributions; equivalents are noted.

## Install what you need

```bash
sudo pacman -S qemu-full libvirt virt-manager edk2-ovmf swtpm dnsmasq
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm "$USER"
```

Log out and back in for the group change to apply.

> **Debian/Ubuntu:** `qemu-system-x86 libvirt-daemon-system virt-manager ovmf
> swtpm` · **Fedora:** `@virtualization` group.

## Bind the GPU to vfio-pci

### Find its PCI IDs

```bash
lspci -Dnn | grep -E '\[030[02]\]'
```

```
0000:02:00.0 VGA compatible controller [0300]: NVIDIA GB203 [RTX 5080] [10de:2c02]
0000:84:00.0 VGA compatible controller [0300]: NVIDIA GA107 [RTX 3050 6GB] [10de:2584]
```

Then list every function of the card you are passing — a GPU is normally two
devices, video and audio:

```bash
lspci -nn -s 84:00
```

```
84:00.0 VGA compatible controller [10de:2584]
84:00.1 Audio device            [10de:2291]
```

You need **both** IDs: `10de:2584,10de:2291`.

> [!CAUTION]
> If both your cards are the same model, they share a vendor:device ID and this
> method would bind **both**, leaving you with no display. In that case bind by
> PCI *address* using a script instead — see the
> [Arch Wiki section on identical devices](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Using_identical_guest_and_host_GPUs).

[`scripts/bind-vfio.sh`](../scripts/bind-vfio.sh) performs these checks and
generates the config below, refusing to proceed if it would capture your host
GPU.

### Write the config

`/etc/modprobe.d/vfio.conf`:

```
options vfio-pci ids=10de:2584,10de:2291
softdep nvidia pre: vfio-pci
softdep nouveau pre: vfio-pci
```

> [!WARNING]
> **Never list your host GPU's ID here.** If you do, your desktop will not come
> back after reboot. Double-check the IDs against `lspci` output before saving.

The `softdep` lines force `vfio-pci` to load before the graphics driver, so it
claims the card first.

> **AMD guest GPU:** add `softdep amdgpu pre: vfio-pci` and `softdep radeon pre:
> vfio-pci` instead of the NVIDIA lines.

### Put vfio in the initramfs

The binding must happen before the graphics driver loads, which on modern
distributions means before userspace.

`/etc/mkinitcpio.conf`:

```
MODULES=(vfio_pci vfio vfio_iommu_type1)
```

```bash
sudo mkinitcpio -P
sudo reboot
```

> **Dracut** (Fedora, and Arch's alternative): create
> `/etc/dracut.conf.d/vfio.conf` with
> `force_drivers+=" vfio_pci vfio vfio_iommu_type1 "` then `sudo dracut -f`.
> **initramfs-tools** (Debian/Ubuntu): add the module names to
> `/etc/initramfs-tools/modules` then `sudo update-initramfs -u`.

### Verify

```bash
lspci -nnk -s 84:00
```

```
84:00.0 VGA compatible controller [10de:2584]
	Kernel driver in use: vfio-pci          ← this is what matters
	Kernel modules: nouveau, nvidia_drm, nvidia
84:00.1 Audio device [10de:2291]
	Kernel driver in use: vfio-pci
```

Both functions on `vfio-pci`, and your desktop still running on the other card.

## Shared memory for Looking Glass

Looking Glass moves frames through a block of memory shared between guest and
host. The `kvmfr` kernel module exposes that block as a device node and enables
zero-copy DMA transfer.

### Install and size it

```bash
# Arch: AUR
yay -S looking-glass-module-dkms looking-glass
```

Size follows the Looking Glass formula — `width × height × 4 × 2`, rounded up to
the next power of two:

| Guest resolution | Minimum |
|---|---|
| 1920×1080 | 32 MB |
| 2560×1440 | 64 MB |
| 3840×2160 | 128 MB |

`/etc/modprobe.d/kvmfr.conf`:

```
options kvmfr static_size_mb=64
```

### Load it at boot

`/etc/modules-load.d/kvmfr.conf`:

```
kvmfr
```

> [!TIP]
> Skipping this file is a common annoyance: the module does not autoload, and
> without `/dev/kvmfr0` the VM refuses to start with `can't open backing store`.
> You then have to remember `sudo modprobe kvmfr` before every session.

### Give QEMU access to it

Two separate permission layers must both allow it.

**Unix permissions** — `/etc/udev/rules.d/99-kvmfr.rules`:

```
SUBSYSTEM=="kvmfr", OWNER="libvirt-qemu", GROUP="kvm", MODE="0660"
```

**libvirt's cgroup device ACL** — in `/etc/libvirt/qemu.conf`, uncomment
`cgroup_device_acl` and append the node:

```
cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/userfaultfd",
    "/dev/kvm", "/dev/rtc", "/dev/hpet",
    "/dev/kvmfr0"
]
```

```bash
sudo systemctl restart libvirtd
```

> [!NOTE]
> This second layer catches people out. Correct `ls -l` permissions are not
> enough — libvirt maintains its own allow-list, and a device missing from it is
> denied regardless of file mode.

### Verify

```bash
ls -l /dev/kvmfr0
```

```
crw-rw---- 1 libvirt-qemu kvm 508, 0 /dev/kvmfr0
```

## Networking

If the VM gets no network despite libvirt's default NAT bridge being up, suspect
your host firewall.

```bash
# UFW is invisible to the usual service checks — it loads through iptables-nft
sudo ufw allow in on virbr0
sudo ufw route allow in on virbr0
```

> [!TIP]
> `systemctl is-active firewalld nftables iptables` can report everything
> inactive while UFW is silently filtering. Check `sudo nft list ruleset` for
> chains named `ufw-*` before concluding there is no firewall.

## Next

[03 — VM setup](03-vm-setup.md)
