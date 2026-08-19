# Windows VM with GPU passthrough + Looking Glass — a field guide

Run a Windows application that needs a **real GPU and real kernel-mode drivers**
from your Linux desktop — in a window, at native speed, without dual-booting and
without giving up your main graphics card.

This guide documents a setup that works, and — more importantly — **how to
diagnose it when it doesn't**.

```
Linux host (main GPU, untouched)  ──┐
                                    ├─► Looking Glass window on your desktop
Windows VM (second GPU, passed) ────┘    shared memory, zero-copy DMA
```

## Why this guide exists

There are already excellent references for the general technique — the
[Arch Wiki PCI passthrough page](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
and the [Looking Glass documentation](https://looking-glass.io/docs). **Read
them.** This guide does not try to replace either.

What is badly documented anywhere is what happens when the thing is *almost*
working: the display comes up but stutters, the capture host dies silently, the
dummy plug hangs your firmware, or the frame rate locks to exactly half of what
you asked for. Every one of those cost hours to diagnose. They are written down
here so they cost you minutes.

**Start at [Troubleshooting](docs/06-troubleshooting.md) if something is already
broken.** It is indexed by symptom.

## What you get

- Windows in a window on your Linux desktop, GPU-accelerated
- Your main GPU never leaves Linux — games and compute keep working
- No display cable swapping, no second monitor, no host reboot to switch
- Unattended startup once configured

## What this is not

- **Not a way to hide virtualization.** Nothing here masks the hypervisor. The
  CPUID hypervisor bit stays set, and virtio devices remain visible. If an
  application refuses to run in a VM, this guide will not change that, and you
  should respect that decision.
- **Not a performance win.** A VM plus capture overhead is always slower than
  running the same software natively on the same hardware.
- **Not beginner-friendly in the "no experience needed" sense.** See below.

## Honest prerequisites

You do **not** need to know anything about VFIO — every step is explained. You
**do** need to be comfortable with:

- a terminal, and editing system configuration files as root
- changing BIOS/UEFI settings
- recovering a machine that will not boot (know how to reach a live USB)

> [!WARNING]
> This process edits your kernel command line and initramfs. A mistake can leave
> your host unbootable. Have a live USB ready before you start. None of the steps
> here are irreversible, but some require rescue media to undo.

Hardware requirements, in order of what stops people:

| Requirement | Why | How to check |
|---|---|---|
| Two GPUs | One stays with Linux, one is handed to the VM | `lspci -nn \| grep -E '\[030[02]\]'` |
| IOMMU support, enabled in BIOS | Required to isolate the GPU for passthrough | [`scripts/check-iommu.sh`](scripts/check-iommu.sh) |
| Clean IOMMU group for the VM's GPU | A group shared with storage or USB cannot be passed safely | same script |
| A free PCIe slot | **Check its electrical width** — see below | [`scripts/pcie-capture-budget.sh`](scripts/pcie-capture-budget.sh) |

> [!IMPORTANT]
> **Check the slot width before you buy anything.** Looking Glass reads every
> frame back over the PCIe link uncompressed. A physically x16 slot wired for one
> lane will cap your frame rate, and no amount of GPU power fixes it. This is the
> single most under-documented constraint in this whole setup —
> [the math is here](docs/05-display-tuning.md#capture-bandwidth).

## Tested platform

Everything in this guide was verified on this machine, in August 2026:

```
Host OS    CachyOS (Arch-based), kernel 6.x
CPU        Intel Core Ultra 7 265KF
Board      Gigabyte B860 DS3H
Host GPU   NVIDIA RTX 5080          (stays with Linux)
Guest GPU  NVIDIA RTX 3050 6GB      (passed to the VM)
Guest OS   Windows 10 Pro 22H2
Stack      QEMU 11.1 · libvirt 12.6 · OVMF 202605 · Looking Glass B7
```

Steps that differ on **AMD** hardware or **non-Arch** distributions are flagged
inline with an `AMD:` or `Non-Arch:` note. Those variants are reasoned from
documentation rather than tested here — treat them as pointers, not gospel.

## Guide

| # | Document | Read it when |
|---|---|---|
| 00 | [Eligibility check](docs/00-eligibility.md) | **First.** Before spending any money. |
| 01 | [Choosing hardware](docs/01-hardware.md) | Picking the second GPU and the display dummy plug |
| 02 | [Host setup](docs/02-host-setup.md) | IOMMU, binding the GPU to vfio-pci, initramfs |
| 03 | [VM setup](docs/03-vm-setup.md) | libvirt XML, the parts that actually matter |
| 04 | [Looking Glass](docs/04-looking-glass.md) | Shared memory, and starting the host reliably |
| 05 | [Display tuning](docs/05-display-tuning.md) | Resolution, refresh rate, EDID, capture bandwidth |
| 06 | [**Troubleshooting**](docs/06-troubleshooting.md) | **Something is broken.** Indexed by symptom. |

## Scripts

| Script | Runs on | Purpose |
|---|---|---|
| [`check-iommu.sh`](scripts/check-iommu.sh) | host | Is this machine capable? Reports IOMMU groups. |
| [`bind-vfio.sh`](scripts/bind-vfio.sh) | host | Generates the vfio-pci binding config safely |
| [`pcie-capture-budget.sh`](scripts/pcie-capture-budget.sh) | host | Reads the real PCIe link width, prints which resolution/refresh combinations fit |
| [`scripts/guest/`](scripts/guest/) | guest | Diagnostics that work **with no visible screen** |

## Contributing

Corrections are very welcome, especially:

- results on AMD hardware, or on distributions other than Arch
- symptoms this guide does not cover
- anywhere the guide is wrong — it is a field report, not a specification

Please include the actual command output rather than a description of it.

## License

[MIT](LICENSE).
