#!/usr/bin/env bash
# Checks whether this machine can do GPU passthrough (VFIO).
#
# Run AFTER enabling VT-d / AMD-Vi in the BIOS and adding
# "intel_iommu=on iommu=pt" (or "amd_iommu=on") to the kernel cmdline.
#
# See docs/00-eligibility.md

set -uo pipefail

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
hdr()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }

hdr "1. CPU virtualization"
if grep -qE '\b(vmx|svm)\b' /proc/cpuinfo; then
  grep -q '\bvmx\b' /proc/cpuinfo && ok "VT-x present (Intel)" || ok "AMD-V present"
else
  bad "No hardware virtualization — enable VT-x / SVM in the BIOS"
fi
[ -e /dev/kvm ] && ok "/dev/kvm present" || bad "/dev/kvm missing (kvm_intel / kvm_amd not loaded?)"
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ok "/dev/kvm accessible by the current user"
else
  warn "/dev/kvm not accessible — add your user to the kvm/libvirt group"
fi

hdr "2. Kernel command line"
if grep -qE 'intel_iommu=on|amd_iommu=on' /proc/cmdline; then
  ok "IOMMU requested on the kernel cmdline"
else
  bad "intel_iommu=on / amd_iommu=on MISSING from the cmdline"
  echo "      current: $(cat /proc/cmdline)"
fi
grep -q 'iommu=pt' /proc/cmdline \
  && ok "iommu=pt active (skips translation for host devices)" \
  || warn "iommu=pt absent (not fatal, small host performance cost)"

hdr "3. IOMMU actually active"
NGROUPS=$(ls /sys/kernel/iommu_groups 2>/dev/null | wc -l)
if [ "$NGROUPS" -eq 0 ]; then
  bad "0 IOMMU groups — VT-d/AMD-Vi disabled in the BIOS, or cmdline not applied"
  echo
  echo "  → Enable VT-d (Intel) or AMD-Vi/IOMMU (AMD) in the BIOS,"
  echo "    then confirm the cmdline above contains intel_iommu=on / amd_iommu=on."
  exit 1
fi
ok "$NGROUPS IOMMU groups detected"

hdr "4. Graphics cards and their groups"
for dev in $(lspci -Dnn | grep -E '\[030[02]\]' | cut -d' ' -f1); do
  for g in /sys/kernel/iommu_groups/*/devices/"$dev"; do
    [ -e "$g" ] || continue
    grp=$(basename "$(dirname "$(dirname "$g")")")
    drv=$(basename "$(readlink -f /sys/bus/pci/devices/$dev/driver 2>/dev/null)" 2>/dev/null || echo "none")
    echo "  $dev  →  group $grp  (driver: $drv)"
    lspci -nns "$dev" | sed 's/^/      /'
  done
done

hdr "5. Contents of each group holding a GPU"
for grp in $(for dev in $(lspci -Dnn | grep -E '\[030[02]\]' | cut -d' ' -f1); do
      for g in /sys/kernel/iommu_groups/*/devices/"$dev"; do
        [ -e "$g" ] && basename "$(dirname "$(dirname "$g")")"
      done
    done | sort -u); do
  echo
  echo "  --- Group $grp ---"
  n=0
  for d in /sys/kernel/iommu_groups/"$grp"/devices/*; do
    lspci -nns "$(basename "$d")" | sed 's/^/      /'
    n=$((n+1))
  done
  # A clean group holds only the GPU and its audio function.
  dirty=$(for d in /sys/kernel/iommu_groups/"$grp"/devices/*; do
            lspci -nns "$(basename "$d")"
          done | grep -icE 'USB|SATA|Ethernet|Network|Non-Volatile memory|SMBus' || true)
  if [ "$dirty" -gt 0 ]; then
    bad "DIRTY group: contains $dirty critical non-GPU device(s)"
    echo "      → passthrough not possible without the ACS override patch"
    echo "        (try the card in another slot first — grouping is per-slot)"
  elif [ "$n" -le 3 ]; then
    ok "clean group ($n device(s)) — usable for passthrough"
  else
    warn "$n devices in this group — inspect manually"
  fi
done

hdr "6. PCIe slot widths (capture bandwidth matters — see docs/00)"
echo "  A physically x16 slot may be wired x4 or even x1. That caps Looking"
echo "  Glass capture regardless of GPU power."
echo
for dev in $(lspci -D | grep -iE 'PCI bridge|Root Port' | cut -d' ' -f1); do
  W="/sys/bus/pci/devices/$dev/max_link_width"
  [ -r "$W" ] || continue
  printf '  %-14s max x%-3s  %s\n' "$dev" "$(cat "$W")" \
    "$(lspci -s "${dev#0000:}" | cut -d' ' -f2- | head -c 55)"
done

hdr "7. ACS (Access Control Services)"
echo "  ACS is what lets the chipset separate groups properly."
if ! sudo -n true 2>/dev/null; then
  warn "ACS check skipped — needs root"
  echo "      re-run with: sudo $0"
else
  found=0
  for dev in $(lspci -D | grep -iE 'PCI bridge|Root Port' | cut -d' ' -f1); do
    if sudo -n lspci -vvs "$dev" 2>/dev/null | grep -q "Access Control Services"; then
      ok "$dev exposes ACS"
      found=$((found+1))
    fi
  done
  [ "$found" -eq 0 ] && warn "no bridge exposes ACS — grouping relies on the hardware layout"
fi

echo
echo "== Summary =="
echo "Clean group for the card you intend to pass  → passthrough viable"
echo "Dirty group                                  → try another slot, then"
echo "                                               consider ACS override"
echo "                                               (weakens isolation)"
