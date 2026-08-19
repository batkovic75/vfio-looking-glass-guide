# 01 — Choosing hardware

Two purchases, both small. The mistakes are in the details.

## The second GPU

This card renders inside the VM. Several things matter, and raw performance is
not one of them.

### It must have real Direct3D support for your workload

If the application is a modern 3D game, size the card for that game as usual.

If it is an older application — anything built on **Direct3D 9** or earlier —
almost any modern card is overkill, but the *driver* still matters:

> [!WARNING]
> **Avoid Intel Arc for old Direct3D titles.** Arc has no native D3D9
> implementation; those calls are translated through D3D9On12, which costs
> performance and introduces compatibility issues. NVIDIA and AMD retain native
> D3D9 drivers.

### It should be modest, and here is why

The capture path — not the rendering — is usually what limits you (see
[00 §3](00-eligibility.md#3-a-free-pcie-slot--and-its-real-electrical-width)).
Money spent on a faster GPU does not buy frames back from a narrow PCIe link.

A used entry-level card from the last few generations is the sweet spot. The
reference machine uses an **RTX 3050 6GB**, bought second-hand for about €100.

### Prefer a card with no external power connector

Cards under ~75 W draw everything from the slot. That means:

- no PSU cable to route, no free PCIe power connector needed
- less heat in a case that now runs two GPUs
- usually a two-slot cooler that fits alongside a large primary card

The RTX 3050 6GB variant is specifically the version without a power connector.
The 8GB variant needs one.

### Check physical fit before ordering

Fitting two GPUs in one case is tighter than it looks. Verify:

- **Length** against your case's clearance
- **Slot thickness** — a 2-slot card in the second slot may be blocked by a
  3-slot primary card's cooler
- **Airflow** — the second card often sits directly under the first, breathing
  its exhaust

## The display dummy plug

This is the part nobody warns you about.

### Why you need one

The Windows capture API used by Looking Glass (**DXGI Desktop Duplication**)
requires an **attached display**. A powered GPU with no monitor produces no
desktop to duplicate — the capture host starts and immediately exits.

A "dummy plug" (also sold as *EDID emulator*, *headless ghost display*, *virtual
display adapter*) is a small connector containing an EEPROM that reports a
monitor's EDID. The GPU believes a screen is attached.

Cost: €5–15.

### What to look for

> [!IMPORTANT]
> Buy one advertised with a **high refresh rate**, not just a high resolution.
> Most cheap plugs advertise "4K" but declare modes like `3840×2160 @ 17Hz` or
> `2560×1440 @ 30Hz`. Resolution is not the useful number here.

| Look for                                  | Avoid                    |
|-------------------------------------------|--------------------------|
| "1080p@120Hz", "1440p@144Hz" in the specs | "4K@30Hz", "…@17Hz" only |
| DisplayPort, if your card has a free one  | —                        |

**DisplayPort is the safer choice** where available: it has no equivalent of
HDMI's TMDS clock ceiling, which is a real obstacle on HDMI plugs
([see 05](05-display-tuning.md#ceiling-2--hdmi-14-tmds-limit)).

### The HDMI trap, and why it is survivable

The reference machine uses an **HDMI** plug labeled "4K 60Hz". That label means
4K at 60 Hz *with 4:2:0 chroma subsampling* — an HDMI 1.4 capability. In
practice the plug negotiates HDMI 1.4 and the driver refuses any mode above
**340 MHz** pixel clock.

That blocks 2560×1440 at 120 Hz (498 MHz) and at 90 Hz (365 MHz) alike — both
sit above 340.

**This is fixable in software** by declaring an HDMI 2.0 data block in the EDID —
[full procedure in 05](05-display-tuning.md#ceiling-2--hdmi-14-tmds-limit). So an
HDMI plug is not a wasted purchase. It is simply extra work you avoid by buying
DisplayPort.

### Buy two

They are cheap, and having a second one lets you distinguish a defective unit
from a structural problem. During this project, testing a second plug is what
proved the UEFI boot hang was inherent to the approach rather than a bad unit.

## What you do not need

- **A second monitor.** The dummy plug replaces it entirely.
- **A KVM switch or display cable swapping.** Looking Glass shows the guest in a
  window on your existing desktop.
- **More RAM than the guest needs.** 8 GB is comfortable for a Windows 10 guest
  running one application.
- **A faster CPU.** Passthrough overhead is small; the reference machine assigns
  6 of its cores to the guest and the host never notices.
