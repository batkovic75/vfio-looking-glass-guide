# 00 — Eligibility check

**Do this before buying anything.** Fifteen minutes here can save you a graphics
card you cannot use.

Three things must be true. If any one fails, stop — the rest of the guide will
not work around it.

## 1. Two GPUs, or the ability to add one

```bash
lspci -nn | grep -E '\[030[02]\]'
```

You should end up with two entries: the card that keeps driving your Linux
desktop, and the card you hand to the VM.

If you only have one today, that is fine — you will buy the second one after
step 3 confirms it will work. See [01 — Choosing hardware](01-hardware.md).

> [!NOTE]
> An integrated GPU counts. If your CPU has working integrated graphics, you can
> run your Linux desktop on it and pass the discrete card to the VM. That is the
> cheapest possible configuration, though it costs you desktop performance.

## 2. IOMMU enabled, with a clean group

The IOMMU is what lets the kernel hand a physical device to a guest safely. It
must be enabled in firmware **and** requested on the kernel command line.

### Enable it in BIOS/UEFI

Look for:

- **Intel:** `VT-d`, sometimes under *Chipset*, *Advanced*, or *Miscellaneous*
- **AMD:** `AMD-Vi` or `IOMMU`, usually under *Advanced → AMD CBS*

Also confirm plain virtualization is on (`VT-x` / `AMD-V` / `SVM`).

### Request it on the kernel command line

Edit `/etc/default/grub`, add to `GRUB_CMDLINE_LINUX_DEFAULT`:

```
intel_iommu=on iommu=pt
```

> **AMD:** use `amd_iommu=on iommu=pt` instead.

Then regenerate and reboot:

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

> **Non-GRUB:** on systemd-boot, edit the `options` line in
> `/boot/loader/entries/*.conf`. On rEFInd, edit `refind_linux.conf`.

### Check the result

```bash
./scripts/check-iommu.sh
```

What you need to see:

```
✔ VT-x present
✔ IOMMU requested on the kernel cmdline
✔ 24 IOMMU groups detected
✔ clean group (2 devices) — usable for passthrough
```

**A "clean" group contains only the GPU and its companion audio function.** If
the group also holds a USB controller, a SATA controller, or your network card,
you cannot pass the GPU without passing those too — which usually means losing
your keyboard or your disk.

> [!CAUTION]
> The common advice for a dirty group is the **ACS override patch**. It works by
> telling the kernel to ignore the grouping the hardware reports. That weakens
> isolation: a compromised guest may reach devices it should not. Acceptable on a
> machine you treat as untrusted anyway; think twice otherwise.

## 3. A free PCIe slot — and its real electrical width

This is the step people skip, and the one that silently caps performance later.

A slot that is physically x16 may be electrically wired for x4, or even x1.
Consumer boards commonly give the CPU's full x16 to the first slot and leave the
rest on a handful of chipset lanes.

Check what your board actually offers:

```bash
# Every PCIe bridge and the width it is capable of
for d in /sys/bus/pci/devices/*/; do
  [ -r "$d/max_link_width" ] || continue
  printf '%s  max x%-3s current x%-3s  %s\n' \
    "$(basename "$d")" \
    "$(cat "$d/max_link_width")" \
    "$(cat "$d/current_link_width" 2>/dev/null || echo '-')" \
    "$(lspci -s "$(basename "$d" | cut -d: -f2-)" 2>/dev/null | cut -d' ' -f2- | head -c 60)"
done | sort
```

Or consult your motherboard manual — search for the block diagram, not the
marketing page.

### Why it matters

Looking Glass copies **every frame, uncompressed**, from the guest GPU's memory
back across the PCIe link. That is a continuous, unavoidable bandwidth cost that
scales with resolution and refresh rate:

```
bytes per second = width × height × 4 × refresh_hz
```

| Mode | Per frame | At that refresh |
|---|---|---|
| 1920×1080 @ 60 | 8.29 MB | 0.50 GB/s |
| 1920×1080 @ 120 | 8.29 MB | 0.99 GB/s |
| 2560×1440 @ 60 | 14.75 MB | 0.88 GB/s |
| 2560×1440 @ 90 | 14.75 MB | 1.33 GB/s |
| 2560×1440 @ 120 | 14.75 MB | 1.77 GB/s |
| 3840×2160 @ 60 | 33.18 MB | 1.99 GB/s |

Against what a link can actually carry (roughly 80 % of theoretical):

| Link | Theoretical | Realistic |
|---|---|---|
| PCIe 3.0 x1 | 0.99 GB/s | ~0.8 GB/s |
| PCIe 4.0 x1 | 1.97 GB/s | ~1.6 GB/s |
| PCIe 3.0 x4 | 3.94 GB/s | ~3.2 GB/s |
| PCIe 4.0 x4 | 7.88 GB/s | ~6.3 GB/s |
| PCIe 4.0 x16 | 31.5 GB/s | ~25 GB/s |

**An x1 slot restricts you to roughly 1440p at 90 Hz, or 1080p at 120 Hz.** An
x4 slot removes the constraint for any realistic desktop resolution.

Once the card is installed, [`pcie-capture-budget.sh`](../scripts/pcie-capture-budget.sh)
reads your actual link and prints the modes that fit.

## Verdict

| Result | What to do |
|---|---|
| All three pass | Continue to [01 — Choosing hardware](01-hardware.md) |
| No IOMMU in BIOS | Stop. Without it, passthrough is impossible. |
| Dirty IOMMU group | Try the GPU in a different slot first — grouping is per-slot. Only then consider ACS override. |
| Only an x1 slot free | Continue, but set expectations using the table above. |
