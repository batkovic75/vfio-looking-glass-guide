# 03 — VM setup

Create the guest in **virt-manager**, then edit the XML for the parts that
matter. Only the decisive fragments are shown here; everything else can stay at
its default.

## Create the VM

In virt-manager, *New virtual machine*:

| Setting  | Value                        | Why                                                   |
|----------|------------------------------|-------------------------------------------------------|
| Firmware | **UEFI** (`OVMF_CODE.4m.fd`) | Modern GPUs expect UEFI; legacy BIOS needs extra work |
| Chipset  | **Q35**                      | i440FX has no proper PCIe                             |
| CPU      | **host-passthrough**         | The guest sees your real CPU                          |
| Memory   | 8 GB                         | Enough for Windows plus one application               |
| Disk bus | **VirtIO**                   | Much faster than emulated SATA                        |
| Network  | **VirtIO**                   | Same reason                                           |
| TPM      | **Emulated (swtpm)**         | Required for Windows 11; harmless on 10               |

Tick *Customize configuration before install*.

> [!TIP]
> Attach the [VirtIO driver ISO](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)
> as a second CD-ROM **before installing**. Windows Setup will not see a VirtIO
> disk without it — load the driver from `viostor\w10\amd64` when the installer
> shows no drives.

Install Windows normally, using the emulated display. Add the GPU afterwards.

## CPU topology and address width

```xml
<vcpu placement='static'>6</vcpu>
<cpu mode='host-passthrough' check='none' migratable='on'>
  <topology sockets='1' dies='1' clusters='1' cores='6' threads='1'/>
  <maxphysaddr mode='passthrough' limit='39'/>
</cpu>
```

Report the cores as belonging to a single socket. Windows licensing limits
physical sockets, and a topology of "6 sockets" can leave you with one usable
core.

> [!IMPORTANT]
> `<maxphysaddr>` is not optional with GPU passthrough on many systems. Without
> it, QEMU may place device BARs above what the IOMMU can map, and the VM fails
> to start with:
> ```
> vfio: DMA mapping failed, unable to continue
> ```
> `limit='39'` corresponds to a 512 GB address space, which is ample. Note that
> `limit` is only valid with `mode='passthrough'` — combining it with
> `mode='emulate'` is rejected by libvirt.

## Passing the GPU

Add **both** functions of the card as PCI host devices:

```xml
<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
    <address domain='0x0000' bus='0x84' slot='0x00' function='0x0'/>
  </source>
  <rom file='/var/lib/libvirt/images/gpu-vbios.rom'/>
</hostdev>
<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
    <address domain='0x0000' bus='0x84' slot='0x00' function='0x1'/>
  </source>
</hostdev>
```

### The vBIOS file

> [!WARNING]
> **Skipping this causes QEMU to crash outright** — a SIGSEGV a few seconds after
> Windows initializes the display, reproducible every time. It is not a guest
> crash; the whole VM process dies.

Consumer graphics cards cannot re-POST inside a VM without an explicit copy of
their video BIOS. Obtain one from
[TechPowerUp's VGA BIOS collection](https://www.techpowerup.com/vgabios/).

Match on **device ID and subsystem ID**, not the model name — vendors ship many
board revisions under one name:

```bash
lspci -nn -s 84:00.0     # gives 10de:2584
lspci -vnn -s 84:00.0 | grep Subsystem   # gives e.g. 1043:89b7
```

Both must match the TechPowerUp entry.

```bash
sudo mv ~/Downloads/275640.rom /var/lib/libvirt/images/gpu-vbios.rom
sudo chown libvirt-qemu:kvm /var/lib/libvirt/images/gpu-vbios.rom
sudo chmod 644 /var/lib/libvirt/images/gpu-vbios.rom
```

> [!NOTE]
> This file is only ever **read** by QEMU. Nothing is written to the card, and
> the physical GPU is never modified. This is not flashing.

## Shared memory device

Looking Glass needs an `ivshmem` device backed by the `kvmfr` node. libvirt's
own `<shmem>` element cannot point at a device file, so use a QEMU passthrough
block:

```xml
<qemu:commandline>
  <qemu:arg value='-device'/>
  <qemu:arg value='{"driver":"ivshmem-plain","id":"shmem0","memdev":"looking-glass"}'/>
  <qemu:arg value='-object'/>
  <qemu:arg value='{"qom-type":"memory-backend-file","id":"looking-glass","mem-path":"/dev/kvmfr0","size":67108864,"share":true}'/>
</qemu:commandline>
```

Two things break this silently:

> [!IMPORTANT]
> - The `<domain>` root element must carry the namespace, or libvirt drops the
>   whole block **without error**:
>   ```xml
>   <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
>   ```
> - `size` must match `static_size_mb` exactly. `67108864` = 64 MiB.

If the block is missing, the Looking Glass **host** crashes on startup with an
assertion in `vector.c` — an error message that gives no hint about its cause.

Verify it survived the edit:

```bash
virsh -c qemu:///system dumpxml <vm-name> | grep ivshmem
```

## Shared folder for diagnostics

Once the dummy plug is attached, the emulated display goes black and you cannot
see the guest. A shared folder is how you keep talking to it — see
[04 §Diagnostics](04-looking-glass.md#diagnostics-without-a-screen).

```xml
<filesystem type='mount' accessmode='passthrough'>
  <driver type='virtiofs'/>
  <source dir='/srv/vm-share'/>
  <target dir='vmshare'/>
  <binary path='/usr/lib/virtiofsd'/>
</filesystem>
```

virtiofs also requires shared memory backing:

```xml
<memoryBacking>
  <source type='memfd'/>
  <access mode='shared'/>
</memoryBacking>
```

In the guest, install [WinFsp](https://winfsp.dev/) and the VirtIO-FS service
from the driver ISO, then map it as `Z:`.

## Input devices

> [!CAUTION]
> **Disable the SPICE guest agent in the guest.** On this setup, the
> `spice-agent` service captured all pointer input and left the mouse completely
> dead inside Windows — with the keyboard still working, which makes it look like
> a hardware problem. Hours were lost swapping emulated tablet/mouse models.
>
> ```powershell
> Stop-Service spice-agent -Force
> Set-Service  spice-agent -StartupType Disabled
> ```
>
> The service is named `spice-agent`, not `vdservice`.

> [!NOTE]
> Changing `<input>` devices with `virsh attach-device --live` appears to succeed
> but does not take effect. Shut the VM down fully and restart it, then confirm
> with `tr '\0' '\n' < /proc/$(pgrep -f 'guest=<vm-name>')/cmdline | grep input`.

## Next

[04 — Looking Glass](04-looking-glass.md)
