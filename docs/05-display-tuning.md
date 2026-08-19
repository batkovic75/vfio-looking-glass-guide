# 05 — Display tuning

This is the part with no good documentation elsewhere, and where a working setup
can still feel bad.

The symptom is always the same — **it runs, but it is not smooth** — and there
are three independent ceilings that produce it. Each one hides the next, so
fixing one can make you think you have solved the problem when you have only
uncovered the following one.

```
Ceiling 1   modes missing from the dummy plug's EDID     → fixed with CRU
Ceiling 2   plug negotiated as HDMI 1.4, 340 MHz limit   → fixed with an HDMI 2.0 block
Ceiling 3   PCIe link too narrow for the capture         → not fixable in software
```

## Reading the counters

Run the client with `-k` and read the overlay:

```
FPS:61.88  UPS:59.89
```

| | Meaning |
|---|---|
| **UPS** | Frames the *host* captures inside the VM |
| **FPS** | Frames the *client* draws on your Linux desktop |

> [!IMPORTANT]
> **Neither number is your application's frame rate.** UPS measures the capture
> chain. An application can render 120 frames per second while UPS reports 60 —
> that is a capture bottleneck, not an application limit. Do not conclude
> anything about the application's engine from these two values alone.

Interpretation:

| Observation | Where to look |
|---|---|
| UPS low, FPS matches it | Inside the VM — capture or display mode |
| UPS high, FPS low | Linux side — compositor, client renderer |
| **UPS is an exact divisor** of the guest refresh rate (60 of 120, 45 of 90) | **VSync is dropping frames** — something in the chain cannot sustain the rate. Go to Ceiling 3. |

That last row is the useful one. A pipeline that *almost* keeps up does not
degrade smoothly — with VSync it snaps to exact divisors. **A perfectly round 60
against a 120 Hz display is a signature, not a coincidence.**

## Ceiling 1 — modes missing from the EDID

Dummy plugs declare very little. A typical HDMI plug's real EDID:

```
Base block
  1920×1080 @  60 Hz  (148.50 MHz)
  1280×720  @  60 Hz  ( 74.25 MHz)
CTA-861 extension block
  2560×1440 @  30 Hz  (120.85 MHz)   ← why Windows falls back to 30 Hz
  2560×1600 @  30 Hz  (134.25 MHz)
  1920×1080 @ 120 Hz  (297.00 MHz)
  3840×2160 @  17 Hz  (151.10 MHz)
```

Ask Windows for 2560×1440 and it picks the only mode it knows at that size:
**30 Hz**. Capture cannot exceed the attached display's refresh rate, so UPS
pins at 29–30 and everything stutters.

Check what is actually active — [`REFRESH.bat`](../scripts/guest/REFRESH.bat):

```
NVIDIA GeForce RTX 3050
  CurrentRefreshRate : 30      ← the cap
  MaxRefreshRate     : 120
```

### Fix: add the mode with CRU

The NVIDIA control panel's *Create custom resolution* button is greyed out when
the GPU is not the primary display adapter — which it never is here, because the
emulated adapter is still present. Use
[**CRU**](https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU)
instead; it edits the EDID in the Windows registry directly.

```
CRU.exe → select the dummy plug's display (not the emulated one)
  Detailed resolutions → Add
    2560 × 1440, <refresh>
    Timing: CVT-RB standard
  OK → run restart64.exe
```

> [!NOTE]
> In CRU 1.5.3 the extension block is labelled **CTA-861**, not CEA-861 — the
> standards body was renamed in 2016.

> [!TIP]
> **Leave only one mode per resolution.** A Direct3D 9 application entering
> exclusive fullscreen enumerates available modes, and nothing obliges it to pick
> the fastest. With 2560×1440 present at both 60 and 120 Hz, one application
> here consistently chose 60. Deleting the slower entry removes the ambiguity.

Windows does not switch automatically: select the new mode under *Settings →
System → Display → Advanced display settings*, choosing the passed-through GPU's
display.

## Ceiling 2 — HDMI 1.4 TMDS limit

With the mode declared, anything above **340 MHz pixel clock** may still be
refused, the driver quietly falling back to 30 Hz.

Cause: without an **HDMI 2.0** data block in the EDID, the output is treated as
HDMI 1.x, capped at 340 MHz TMDS character rate. Per CRU's documentation, HDMI is
treated as single-link DVI unless an HDMI support data block exists, and HDMI 2.0
rates require *both* an HDMI support block and an HDMI 2.0 block.

```
HDMI 1.4 ceiling   340 MHz
HDMI 2.0 ceiling   600 MHz

1920×1080 @ 120  ≈ 297 MHz   under 340 — works either way
2560×1440 @  60  ≈ 237 MHz   under 340 — works either way
2560×1440 @  90  ≈ 365 MHz   needs the HDMI 2.0 block
2560×1440 @ 120  ≈ 498 MHz   needs the HDMI 2.0 block
```

A plug sold as "4K@60Hz (4:2:0)" is telling you it is HDMI 1.4 — 4:2:0 chroma
subsampling halves the bandwidth, which is how 4K60 fits under 340 MHz.

### Fix: declare HDMI 2.0

```
CRU.exe → select the dummy plug's display

1. Extension blocks → select "CTA-861" → Edit
     Data blocks → Add → HDMI 2.0 support
       Max TMDS clock : 600 MHz
       SCDC present   : CHECKED          ← mandatory
     OK → OK

2. Detailed resolutions → Add
     2560 × 1440 @ 90 Hz, Timing: CVT-RB standard
     (check the reported pixel clock: ~365 MHz)

3. OK → run restart64.exe
```

> [!IMPORTANT]
> **`SCDC present` is not optional.** Above 340 Mcsc, HDMI 2.0 mandates TMDS
> scrambling, which the source signals to the sink over the Status and Control
> Data Channel. Without SCDC declared, a compliant driver refuses to exceed
> 340 MHz *even though* the Maximum field says 600.

> [!NOTE]
> The `Max TMDS clock` field inside the older **HDMI support** block can stay at
> its default (often 300 MHz). The two fields cover disjoint ranges: the 1.4
> block governs rates up to 340 MHz, the HDMI 2.0 block everything above.
> Verified unnecessary to change on NVIDIA. CRU's documentation notes that AMD
> and Intel drivers *also* read the 1.4 field — worth trying there if stuck.

> [!WARNING]
> `restart64.exe` restarts the graphics driver, which **kills the Looking Glass
> host**. Harmless once the watchdog from [04](04-looking-glass.md#the-fix-a-scheduled-task-with-a-watchdog)
> is in place. Without it, you are left with a black screen and nothing to click.

Recovery if a mode breaks the display: unplug the dummy plug to fall back to the
emulated adapter. CRU ships `reset-all.exe`, which reverts every change.

## Capture bandwidth

**Ceiling 3, and the one that cannot be fixed in software.**

Looking Glass reads every frame back from the guest GPU's memory, uncompressed
BGRA, across the PCIe link:

```
bytes/second = width × height × 4 × refresh_hz
```

On the reference machine the GPU sits in a slot wired for a single lane:

```
/sys/bus/pci/devices/0000:84:00.0/
  max_link_width       16
  current_link_width   1        ← one lane

upstream root port (0000:80:1d.0)
  max_link_width       1        ← the port itself is x1
```

Because the *root port* is limited, this is not a seating fault, a failed
negotiation, or M.2 lane sharing. The board simply has one x16 slot — occupied by
the host GPU — and four x1 slots.

```
PCIe 4.0 x1 → 1.97 GB/s theoretical, ~1.6 GB/s realistic

1920×1080 @ 120  =  8.29 MB × 120  =  0.99 GB/s   OK
2560×1440 @  60  = 14.75 MB ×  60  =  0.88 GB/s   OK
2560×1440 @  90  = 14.75 MB ×  90  =  1.33 GB/s   OK
2560×1440 @ 120  = 14.75 MB × 120  =  1.77 GB/s   exceeds the link
```

This explains an observation that otherwise looks absurd — **120 fps at 1080p but
60 at 1440p** — even though both ask for a nearly identical pixel rate:

```
1920×1080 × 120 = 249 Mpixel/s
2560×1440 ×  60 = 221 Mpixel/s
```

Resolution is not what saturates the link. **Bytes are.** And when the link
saturates, VSync drops to an exact divisor — hence a suspiciously round 60.

Compute your own budget:

```bash
./scripts/pcie-capture-budget.sh
```

### What does not help

All four of these were tested and measured on the reference machine:

| Hypothesis | Result |
|---|---|
| Buy a better dummy plug (DisplayPort) | **No.** The HDMI 2.0 block lifts the EDID ceiling on the existing plug. |
| The GPU is too weak / saturated | **No.** `utilization.gpu` measured 64 %, never 100 %. |
| The GPU is stuck at low clocks | **No.** Locked to 2017 MHz with `nvidia-smi --lock-gpu-clocks`, plus *Prefer maximum performance*: no change. |
| The application caps itself at 60 | **No.** It reaches 120 at 1080p, and exposes no VSync or frame-limit setting. |

> [!IMPORTANT]
> **A more powerful GPU would change nothing.** The bottleneck is reading the
> framebuffer back through one PCIe lane — entirely independent of rendering
> power. The only hardware fix is a motherboard with a second wide slot, which
> means replacing the platform.

## Choosing your mode

Work through it in this order:

1. **Measure your link** — `pcie-capture-budget.sh`
2. **Pick a target** from the modes it says fit, favouring resolution over
   refresh rate for 2D or slow-paced applications, the reverse for fast action
3. **Create exactly that mode** in CRU, and delete the other entries at the same
   resolution
4. **Verify UPS** matches the refresh rate you chose

The reference machine settled on **2560×1440 @ 90 Hz** — the highest step its x1
link sustains, giving 78 % more pixels than 1080p at a refresh rate that stays
smooth.

Intermediate refresh rates are legitimate and underused. You are not restricted
to 60 and 120: if 120 does not fit and 60 wastes headroom, create 75, 90, or 100.

## Next

[06 — Troubleshooting](06-troubleshooting.md)
