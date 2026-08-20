# 04 — Looking Glass

Looking Glass has two halves: a **host** application inside Windows that captures
the desktop into shared memory, and a **client** on Linux that displays it. Most
problems come down to the host silently not running.

## Install the host in the guest

Download the host installer matching your client version exactly
([looking-glass.io/downloads](https://looking-glass.io/downloads)) and run it in
the guest. Version mismatch between host and client is not tolerated.

## The dummy plug rule

> [!CAUTION]
> **Never boot the VM with the dummy plug attached.** The firmware hangs on the
> TianoCore splash with a spinner, indefinitely. It is not a crash — the VM
> simply never boots.
>
> Worse: **unplugging it afterwards does not recover the boot.** PCI enumeration
> has already happened. The only way out is `virsh destroy` followed by a fresh
> start, which is safe because Windows never started.
>
> Verified on two separate plugs (from the same multipack, so a shared defect is
> not fully excluded — but the mechanism points to firmware, not the plug). A
> single boot that succeeds with the plug attached is luck, not a sign the
> constraint has gone.

The working order is therefore:

```
1. Start the VM with no plug
2. Log into Windows (visible on the emulated display)
3. Hot-plug the dummy plug     → emulated display goes black, expected
4. The capture host starts and Looking Glass takes over
```

Step 3 turning the screen black is correct: Windows moves the desktop onto the
passed-through GPU, and the emulated adapter goes idle.

## Starting the host reliably

The host needs administrator rights — without them it prints `Access is denied.`
and exits. Launching it from a self-elevating script produces a UAC prompt, and
that creates two problems.

> [!WARNING]
> **The UAC dialog's default button is "No".** Pressing Enter blind — which is
> tempting when the screen is black — *refuses* elevation. This silently defeats
> every "just press Enter" recovery attempt.

And after any graphics driver restart, the host dies while the screen is already
black, leaving nothing to click.

### The fix: a scheduled task with a watchdog

Register the host as a scheduled task that runs with highest privileges at
logon, **and repeats every minute**:

```powershell
$exe = "C:\Program Files\Looking Glass (host)\looking-glass-host.exe"

$action  = New-ScheduledTaskAction -Execute $exe
$trigger = New-ScheduledTaskTrigger -AtLogOn
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 30)).Repetition

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -RunLevel Highest -LogonType Interactive
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName "LookingGlassHost" `
        -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Force
```

Ready-made scripts: [`LG-INSTALL.bat`](../scripts/guest/LG-INSTALL.bat) and
[`lgtask.ps1`](../scripts/guest/lgtask.ps1). Run once, accept the UAC prompt —
the last one you will see.

What this buys you:

- **No UAC prompt** at startup, ever again
- The host **restarts itself within a minute** after a driver restart, a crash,
  or the plug being removed and reattached
- `MultipleInstances IgnoreNew` prevents duplicates while it is running
- The plug can be attached **whenever you like** — while it is absent the host
  fails quietly and retries; when it appears, capture begins

Two mistakes worth avoiding, both cost time here:

> [!NOTE]
> - **Do not gate elevation on `net session`.** It returned a false positive,
>   letting the script run unelevated while `schtasks` answered `Access is
>   denied.` Re-invoke unconditionally through `RunAs` with an argument marker
>   instead.
> - **`[TimeSpan]::MaxValue` is rejected** by Task Scheduler — it serializes to
>   `P99999999DT23H59M59S`, which fails validation with *"value out of range"*.
>   Use a bounded duration; the window restarts at every logon anyway.

## Start the client

```bash
looking-glass-client -f /dev/kvmfr0 -k
```

`-k` overlays the FPS/UPS counters. Keep it on — it is the primary diagnostic
instrument ([05](05-display-tuning.md#reading-the-counters)).

A healthy startup log:

```
ivshmem.c:137 | ivshmemOpenDev  | KVMFR Device : /dev/kvmfr0
main.c:1733   | lg_run          | Starting session
main.c:553    | main_frameThread| Using DMA buffer support        ← zero-copy
main.c:710    | main_frameThread| Format: FRAME_TYPE_BGRA 2560x1440
```

If instead you see `The host application seems to not be running`, the client is
fine and the guest-side host is the problem.

### Escape key

Looking Glass captures your keyboard. The default release key is **Scroll
Lock**, which many keyboards no longer have — leaving you trapped.

`~/.config/looking-glass/client.ini`:

```ini
[input]
escapeKey=KEY_RIGHTCTRL
```

Loaded automatically; no command-line flag needed.

> [!CAUTION]
> **Never run virt-manager's console and the Looking Glass client at the same
> time.** They compete for the same SPICE channel and disconnect each other.
> Close the virt-manager viewer window before starting the client.

## Daily use

The whole sequence is scripted:

```bash
VM=my-guest ./scripts/start-vm.sh
VM=my-guest ./scripts/stop-vm.sh
```

`start-vm.sh` verifies the shared memory device and the vfio-pci binding before
touching anything, reminds you to unplug the dummy plug, boots the VM, and
attaches the viewer immediately — so boot and login are visible through the
SPICE fallback, and virt-manager is never needed.

> [!TIP]
> **Closing the Looking Glass window does not stop the VM.** It only stops the
> display; the guest keeps running with the GPU powered. `start-vm.sh` says so
> when the viewer exits and offers to shut down; `stop-vm.sh` handles the case
> where the viewer is already closed.

`stop-vm.sh` does an ACPI shutdown and only offers a hard cut after two minutes,
explaining both likely causes. That restraint matters: repeated hard resets are
what feed the [PCIe reset bug](07-troubleshooting.md#gpu-vanished-from-the-guest).

## Diagnostics without a screen

Once the plug is attached the emulated display is black, so you cannot see the
guest to fix it. The solution is a shared folder and scripts that write their
output to files you read from Linux.

Copy the scripts from [`scripts/guest/`](../scripts/guest/) into the shared
folder, mapped as `Z:` in the guest.

| Script           | Purpose                                        | Needs admin |
|------------------|------------------------------------------------|-------------|
| `DIAG.bat`       | Video adapters and monitors (WMI + PnP)        | no          |
| `REFRESH.bat`    | Actual resolution and refresh rate, EDID modes | no          |
| `GPUCHECK.bat`   | Instantaneous GPU load                         | no          |
| `GPUWATCH.bat`   | **Delayed** GPU sampling — see below           | no          |
| `LG-INSTALL.bat` | Install the scheduled task                     | yes         |
| `LGGO.bat`       | Restart the host via `schtasks /run`           | no          |

Read the results from the host:

```bash
cat /srv/vm-share/refresh.txt
```

> [!IMPORTANT]
> **Batch files must have CRLF line endings.** A `.bat` saved with Unix endings
> fails in confusing ways under `cmd.exe`.

> [!TIP]
> **Measuring GPU load from a `.bat` gives a false reading.** Switching to the
> script moves an exclusive-fullscreen application to the background, where it
> stops rendering — you end up measuring an idle desktop. `GPUWATCH.bat` waits
> 15 seconds before sampling so you can return to the application first.

### Do not try to drive the guest blind

`virsh send-key` is a tempting escape hatch. It is not reliable here: an
application running in exclusive fullscreen grabs the keyboard, so `Win+R` never
reaches the desktop. Several attempts failed this way before the cause was
understood.

When the screen is black, use in order:

1. **Wait a minute** — the watchdog restarts the host
2. **Unplug the dummy plug** — Windows moves the desktop back to the emulated
   display, visible again in virt-manager or the client's SPICE fallback

## Next

[05 — Display tuning](05-display-tuning.md)
