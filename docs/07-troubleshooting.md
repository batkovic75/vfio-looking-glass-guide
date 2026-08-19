# 07 — Troubleshooting

Indexed by **what you observe**. Every entry here was hit and diagnosed on real
hardware.

## Quick index

| Symptom                                                 | Section                                                          |
|---------------------------------------------------------|------------------------------------------------------------------|
| QEMU crashes seconds after the guest initializes video  | [Host process dies](#qemu-crashes-when-video-starts)             |
| `vfio: DMA mapping failed, unable to continue`          | [DMA mapping](#vfio-dma-mapping-failed)                          |
| `can't open backing store /dev/kvmfr0`                  | [Shared memory permissions](#cant-open-backing-store-devkvmfr0)  |
| VM hangs on the TianoCore splash forever                | [UEFI hang](#vm-hangs-on-the-tianocore-splash)                   |
| Looking Glass host exits immediately                    | [Host will not start](#looking-glass-host-exits-immediately)     |
| Client says *host application seems to not be running*  | [Host will not start](#looking-glass-host-exits-immediately)     |
| Client crashes with an assertion in `vector.c`          | [Missing ivshmem](#client-or-host-asserts-in-vectorc)            |
| Black screen and nothing responds after `restart64.exe` | [Recovering a black screen](#black-screen-with-nothing-to-click) |
| Mouse dead in the guest, keyboard fine                  | [Mouse](#mouse-dead-in-the-guest)                                |
| An application launches but nothing appears             | [Invisible UAC](#applications-launch-but-nothing-appears)        |
| Stutter, UPS stuck around 30                            | [Refresh rate](#stutter-with-ups-around-30)                      |
| Frame rate locked to exactly half the refresh rate      | [Capture bandwidth](#frame-rate-locked-to-exactly-half)          |
| GPU missing from Device Manager, one display only       | [Reset bug](#gpu-vanished-from-the-guest)                        |
| Guest has no network                                    | [Networking](#guest-has-no-network)                              |

---

## QEMU crashes when video starts

**Symptom.** The whole QEMU process dies with `SIGSEGV`, a few seconds after
Windows initializes the passed-through display. Reproducible every time.

**Cause.** Consumer GPUs cannot re-POST inside a VM without an explicit copy of
their video BIOS.

**Fix.** Add a `<rom file>` to the video function's `<hostdev>` —
[03 §The vBIOS file](03-vm-setup.md#the-vbios-file). Match the ROM on device
**and subsystem** ID.

---

## vfio: DMA mapping failed

**Symptom.** VM refuses to start:

```
vfio: DMA mapping failed, unable to continue
```

Often mentioning a peer-to-peer BAR.

**Cause.** QEMU places device BARs above the address range the IOMMU can map.

**Fix.**

```xml
<cpu mode='host-passthrough' check='none' migratable='on'>
  <maxphysaddr mode='passthrough' limit='39'/>
</cpu>
```

`limit` is only valid with `mode='passthrough'`; libvirt rejects it alongside
`mode='emulate'`.

---

## can't open backing store /dev/kvmfr0

**Symptom.** VM will not start, QEMU log names `/dev/kvmfr0`.

**Cause.** Two independent permission layers. Correct Unix permissions are not
enough — libvirt keeps its own device allow-list.

**Fix.** Check in order:

```bash
lsmod | grep kvmfr           # module loaded?
ls -l /dev/kvmfr0            # libvirt-qemu:kvm, mode 0660?
grep -A12 cgroup_device_acl /etc/libvirt/qemu.conf   # /dev/kvmfr0 listed?
```

Details in [02 §Give QEMU access](02-host-setup.md#give-qemu-access-to-it). After
editing `qemu.conf`, `sudo systemctl restart libvirtd`.

If the module is missing after a host reboot, you skipped
`/etc/modules-load.d/kvmfr.conf`.

---

## VM hangs on the TianoCore splash

**Symptom.** The VM stops at the OVMF logo with a spinner and never boots.

**Cause.** The dummy plug was attached at power-on.

**Fix.** Power the VM off — `virsh destroy <vm>`, safe because Windows never
started — then boot with the plug **removed** and attach it after logging in.

> Unplugging while it is hung does **not** help. PCI enumeration has already
> happened. Verified on two separate plugs; a single successful boot with the
> plug attached is luck, not a change in behavior.

---

## Looking Glass host exits immediately

Work through these in order.

**1. Is a display actually attached?** DXGI Desktop Duplication requires one. A
powered GPU with no monitor and no dummy plug has no desktop to duplicate, and
the host exits. Attach the plug.

**2. Is it running as administrator?** Without elevation it prints `Access is
denied.` and quits. Use the scheduled task from
[04](04-looking-glass.md#the-fix-a-scheduled-task-with-a-watchdog).

**3. Do host and client versions match?** They must be the same release.

**4. Is the shared memory device present?** See
[`vector.c`](#client-or-host-asserts-in-vectorc) below.

---

## Client or host asserts in vector.c

**Symptom.** An assertion failure in `vector.c`, with nothing indicating a cause.

**Cause.** The `ivshmem` device is missing from the VM. Usually because the
`<qemu:commandline>` block was dropped — libvirt discards it **without any
error** if the `<domain>` element lacks the qemu namespace.

**Fix.**

```bash
virsh -c qemu:///system dumpxml <vm> | grep ivshmem
```

Nothing? Restore the block and the namespace —
[03 §Shared memory device](03-vm-setup.md#shared-memory-device).

> Chasing this as a Looking Glass bug is a dead end; check the XML first.

---

## Black screen with nothing to click

**Symptom.** After `restart64.exe`, a driver crash, or unplugging the dummy plug,
the Looking Glass window goes black. The guest is running — you may still hear
audio — but there is no visible desktop.

**Cause.** The capture host died while the desktop lives on the passed-through
GPU, which only the host can show you.

**Fix**, in order:

1. **Wait one minute.** With the watchdog task installed, the host restarts by
   itself. This is the normal path.
2. **Unplug the dummy plug.** Windows moves the desktop back to the emulated
   adapter, visible in virt-manager or the client's SPICE fallback. Log in, fix
   what you need, re-attach the plug.

> [!CAUTION]
> **Do not try to drive the guest blind with `virsh send-key`.** If an
> application is running in exclusive fullscreen it grabs the keyboard and
> `Win+R` never reaches the desktop. And remember the UAC dialog's default button
> is **No** — a blind Enter refuses elevation rather than granting it.

---

## Mouse dead in the guest

**Symptom.** Keyboard works, mouse does not — in Windows, but fine in the
installer.

**Cause.** The `spice-agent` service captures all pointer input.

**Fix.**

```powershell
Stop-Service spice-agent -Force
Set-Service  spice-agent -StartupType Disabled
```

> This looks exactly like a hardware/emulation problem, and cycling emulated
> tablet and mouse models produces no improvement. The service is named
> `spice-agent`, not `vdservice`.

Also note: changing `<input>` devices with `virsh attach-device --live` appears
to succeed but does not apply. Restart the VM fully.

---

## Applications launch but nothing appears

**Symptom.** You start something, nothing happens, the screen looks frozen — then
pressing Enter suddenly unblocks it.

**Cause.** UAC dialogs render on the **secure desktop**, a separate layer Looking
Glass does not capture.

**Fix.**

```bat
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" ^
  /v PromptOnSecureDesktop /t REG_DWORD /d 0 /f
```

> [!WARNING]
> This is a real security trade-off: the secure desktop exists to stop already-
> present malware from faking UAC approval. Acceptable on an isolated VM. Set it
> back to `1` to revert.

Better still, remove the need for UAC entirely with the scheduled task from
[04](04-looking-glass.md#the-fix-a-scheduled-task-with-a-watchdog).

---

## Stutter with UPS around 30

**Symptom.** Everything looks correctly configured, but the image is choppy and
the UPS counter sits at 29–30.

**Cause.** The virtual display is running at 30 Hz. Capture can never exceed the
attached display's refresh rate.

**Diagnose.** Run [`REFRESH.bat`](../scripts/guest/REFRESH.bat):

```
CurrentRefreshRate : 30      ← the cap
MaxRefreshRate     : 120
```

Windows chose a resolution the plug's EDID only declares at 30 Hz.

**Fix.** Create the mode you want with CRU —
[05 §Ceiling 1](05-display-tuning.md#ceiling-1--modes-missing-from-the-edid).

---

## Frame rate locked to exactly half

**Symptom.** The display is at 120 Hz, Windows confirms it, but you get exactly
60. Or 90 Hz gives exactly 45.

**Cause.** VSync dropping to an exact divisor because something cannot sustain
the full rate. Round numbers are the tell — a rendering or thermal limit would
give ragged values like 87 or 103.

**Diagnose.** Compute the capture bandwidth against your PCIe link:

```bash
./scripts/pcie-capture-budget.sh
```

**Fix.** Choose a refresh rate that fits the budget — including intermediate
values like 75, 90 or 100, which you can create in CRU. Full reasoning in
[05 §Capture bandwidth](05-display-tuning.md#capture-bandwidth); the
measurements that ruled out GPU power, GPU clocks and application limits are in
[06 §Levers that did nothing](06-performance.md#levers-that-did-nothing).

---

## GPU vanished from the guest

**Symptom.** Device Manager no longer lists the passed-through GPU, only one
display is detected — while `lspci` on the host still shows it bound to
`vfio-pci`.

**Cause.** The PCIe reset bug. Consumer GeForce cards do not always reset cleanly
between VM runs. It builds up over repeated VM stop/start cycles.

Host-side signature:

```bash
journalctl -k -b | grep vfio_bar_restore
# vfio-pci 0000:84:00.0: vfio_bar_restore: reset recovery - restoring BARs
```

**Fix. Reboot the Linux host.** There is no lighter remedy.

> [!CAUTION]
> **PCI hot remove/rescan does not recover it.** Tested:
> ```bash
> # DOES NOT WORK for this — documented so you do not retry it
> sudo sh -c 'echo 1 > /sys/bus/pci/devices/0000:84:00.0/remove;
>             sleep 2; echo 1 > /sys/bus/pci/rescan'
> ```
> After this the card disappeared from the bus entirely — no
> `/sys/bus/pci/devices/0000:84:00.*` at all. A consumer GeForce needs a real
> power cycle, which a software rescan does not provide.

**Prevention.** Repeated VM stop/start cycles trigger it. Normal use — one boot,
one session — does not.

---

## Guest has no network

**Symptom.** No connectivity in the guest even though libvirt's default NAT
network is active.

**Cause.** A host firewall filtering the bridge. UFW is the usual culprit and is
easy to miss.

**Diagnose.**

```bash
systemctl is-active firewalld nftables iptables    # may all say inactive
sudo nft list ruleset | grep -c 'ufw-'             # but this is non-zero
```

UFW loads through `iptables-nft`, so the standard service checks report nothing.

**Fix.**

```bash
sudo ufw allow in on virbr0
sudo ufw route allow in on virbr0
```

---

## Still stuck?

Useful things to gather before asking anywhere:

```bash
lspci -nnk -s <gpu-address>                    # driver binding
virsh -c qemu:///system dumpxml <vm>           # full VM definition
sudo tail -50 /var/log/libvirt/qemu/<vm>.log   # QEMU errors
journalctl -k -b | grep -iE 'vfio|iommu'       # kernel side
looking-glass-client -f /dev/kvmfr0 -k 2>&1 | head -40
```

And from inside the guest, `%ProgramData%\Looking Glass (host)\looking-glass-host.txt`.

Please include actual output rather than a description — most of the entries
above were solved by reading one specific line in one of these.
