# Guest-side scripts

Copy these into the folder shared with the guest (see
[03 §Shared folder](../../docs/03-vm-setup.md#shared-folder-for-diagnostics)),
mapped as `Z:` inside Windows.

They exist because **once the dummy plug is attached, the emulated display goes
black** and you cannot see the guest. Each script writes its output to a `.txt`
file in the share, which you read from Linux:

```bash
cat /srv/vm-share/refresh.txt
```

| Script | Purpose | Admin |
|---|---|---|
| `LG-INSTALL.bat` + `lgtask.ps1` | Install the `LookingGlassHost` scheduled task (auto-start + 1-minute watchdog). **Run once.** | yes |
| `LGGO.bat` | Restart the host via `schtasks /run` | no |
| `DIAG.bat` | Video adapters and monitors (WMI + PnP) | no |
| `REFRESH.bat` | Real resolution and refresh rate, plus EDID modes | no |
| `GPUCHECK.bat` | Instantaneous GPU load | no |
| `GPUWATCH.bat` | **Delayed** GPU sampling — 15 s, then 8 samples | no |

> [!IMPORTANT]
> **These files must keep CRLF line endings.** A `.bat` saved with Unix line
> endings fails in confusing ways under `cmd.exe`. If you edit them on Linux,
> check with `file *.bat` — it should say *"with CRLF line terminators"*.

> [!TIP]
> `GPUCHECK.bat` measures whatever is on screen *now*. Switching to it from an
> exclusive-fullscreen application sends that application to the background,
> where it stops rendering — so you measure an idle desktop and conclude the GPU
> is idle. `GPUWATCH.bat` waits 15 seconds first so you can switch back.

The `nvidia-smi` scripts are NVIDIA-specific. On AMD, substitute
`rocm-smi` or read `/sys/class/drm/card*/device/gpu_busy_percent` from the host.
