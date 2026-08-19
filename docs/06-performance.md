# 06 — Performance

What to expect, where the cost actually is, and how to measure it rather than
guess.

Every number here was measured on the [reference
machine](../README.md#tested-platform). Yours will differ — the method matters
more than the figures.

## What this setup costs you

Three separate things happen between the application and your eyes, and they cost
very different amounts.

| Stage                      | Overhead          | Notes                                                                       |
|----------------------------|-------------------|-----------------------------------------------------------------------------|
| **Rendering** in the guest | Near-native       | A real GPU with its real driver. This is the whole point of passthrough.    |
| **CPU / memory**           | Small             | KVM uses hardware virtualization. The host barely notices 6 assigned cores. |
| **Capture + transfer**     | **The real cost** | Every frame is read back from the GPU, uncompressed, over PCIe.             |

> [!IMPORTANT]
> The capture stage is the one people forget, and the only one that scales
> badly. It is a fixed cost per frame, so it grows with **resolution × refresh
> rate** — not with how demanding your application is.

That asymmetry produces a counter-intuitive result: a light application at high
resolution can hit the ceiling while a demanding one at lower resolution sails
through.

## Measured results

Reference machine, guest GPU in a **PCIe 4.0 x1** slot:

| Guest mode         | UPS achieved | Verdict                         |
|--------------------|--------------|---------------------------------|
| 1920×1080 @ 120 Hz | 120          | smooth                          |
| 2560×1440 @ 60 Hz  | 60           | smooth                          |
| 2560×1440 @ 90 Hz  | 90           | smooth — **retained**           |
| 2560×1440 @ 120 Hz | 60           | VSync halved it; link saturated |

GPU load while running at 1440p90: **62–64 % utilization**, 405 MB VRAM, 47 °C.
The card is not the limit — see below.

## How to measure

### 1. Looking Glass counters

```bash
looking-glass-client -f /dev/kvmfr0 -k
```

`UPS` is frames captured inside the VM; `FPS` is frames drawn on your Linux
desktop.

> [!WARNING]
> **Neither is your application's frame rate.** UPS measures the capture chain.
> An application rendering 120 fps will still show UPS 60 if capture cannot keep
> up. Do not diagnose the application from these numbers.

Full interpretation table in
[05 §Reading the counters](05-display-tuning.md#reading-the-counters).

### 2. GPU load in the guest

Use [`GPUWATCH.bat`](../scripts/guest/GPUWATCH.bat), not a direct query.

> [!CAUTION]
> **Switching to a script sends a fullscreen application to the background,
> where it stops rendering.** A direct measurement therefore reports an idle
> desktop. The first attempt here read 30 % load with the application absent from
> the process list entirely — a completely misleading result. `GPUWATCH.bat`
> waits 15 seconds so you can switch back first.

Read both **utilization and clock speed**:

```
64 %, 780 MHz, 2160 MHz, 405 MiB
     ^^^^^^^^  ^^^^^^^^
     current   maximum
```

64 % at 780 MHz out of 2160 is roughly 23 % of the card's real capability. A high
utilization figure at a low clock does not mean the GPU is the bottleneck.

### 3. Capture budget

```bash
./scripts/pcie-capture-budget.sh
```

Reads your actual link width and prints which resolution/refresh combinations
fit. On the reference machine its verdicts match all four measured results above.

## Levers that did nothing

All measured, not assumed. Save yourself the time:

| Lever                                                    | Result                                                                                      |
|----------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Locking GPU clocks (`nvidia-smi --lock-gpu-clocks=2160`) | **No change.** Clock rose from 780 to 2017 MHz, frame rate identical.                       |
| NVIDIA *Prefer maximum performance* power mode           | **No change.**                                                                              |
| A better dummy plug                                      | **No change** to throughput. It lifts the EDID ceiling, not the link.                       |
| A more powerful GPU                                      | **Would not help.** The bottleneck is framebuffer readback, independent of rendering power. |

> [!NOTE]
> The GPU clock sitting at 780 MHz looked like a smoking gun — a card refusing to
> boost. It was a red herring: the clock was low precisely *because* there was
> nothing to do while waiting on the link.

## Levers that work

**Pick a mode inside your bandwidth budget.** By far the largest effect. If
120 Hz does not fit and 60 wastes headroom, create 75, 90 or 100 in CRU — you
are not limited to the usual values. See
[05 §Choosing your mode](05-display-tuning.md#choosing-your-mode).

**Size the Looking Glass window 1:1** with the captured resolution. Any other
size makes the client rescale, which costs host GPU time and softens the image.

**Trim guest-side overlays.** The Xbox Game Bar injects itself into applications
and shows up in the GPU process list. Disable it under *Settings → Gaming → Xbox
Game Bar*.

**Assign enough cores, in one socket.** Report them as cores of a single socket
([03](03-vm-setup.md#cpu-topology-and-address-width)) — Windows licensing limits
sockets, and a bad topology can leave you with one usable core.

## Untested levers

These are standard VFIO tuning practice and likely to help on latency-sensitive
workloads. **They were not measured here**, so treat them as leads:

- **CPU pinning** — pin guest vCPUs to specific host cores, with `isolcpus` or
  `<cputune>`, so the scheduler stops migrating them
- **Hugepages** — back guest memory with 2 MB or 1 GB pages to cut TLB pressure
- **MSI interrupts** — enable for the passed-through GPU's audio function, a
  known fix for crackling sound

The [Arch Wiki](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF) covers
all three properly.

## Setting expectations

For an application that would run at 200 fps on bare metal, this setup will not
match it — you are paying for capture and transfer, always.

What you get instead is the application running **at native rendering quality,
in a window, alongside your Linux desktop**, with no reboot and no cable
swapping. Whether that trade is worth it depends entirely on what you are
running.

If your PCIe slot is wide (x4 or better), the capture cost largely disappears at
desktop resolutions and the trade becomes very favorable. If it is x1, choose
your mode deliberately using the budget script and the result is still perfectly
usable — the reference machine settled on 1440p at 90 Hz and it is smooth.

## Next

[07 — Troubleshooting](07-troubleshooting.md)
