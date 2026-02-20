#!/usr/bin/env bash
# Prerequisites: EDL mode and fastboot.
# Usage: 
#   ./flash.sh         - Full flash (firmware + boot + rootfs)
#   ./flash.sh -l      - Lite flash (only boot + rootfs)
# Notes:
# - Automatically detects "firmware.zip" in files/, extracts .mbn files to a temp dir, and uses them.
# - Falls back to manual directory selection if the ZIP is not found.

set -euo pipefail

# Parse arguments
LITE_MODE=false
while getopts "l" opt; do
    case $opt in
        l)
            LITE_MODE=true
            ;;
        *)
            echo "Usage: $0 [-l]"
            echo "  -l    Lite mode: Only flash boot and rootfs (skip firmware and GPT)"
            exit 1
            ;;
    esac
done

# Find a file by pattern at a given directory depth.
find_image() {
    local dir="$1"
    local pattern="$2"
    local file
    file=$(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | head -n 1 || true)
    if [[ -z "${file:-}" ]]; then
        echo "[-] Error: Image not found with pattern: $pattern" >&2
        return 1
    fi
    echo "$file"
}

echo "=== Alpine/Arch Linux ARM Flash Script ==="
if [[ "$LITE_MODE" == true ]]; then
    echo "[*] Mode: LITE (boot + rootfs only)"
else
    echo "[*] Mode: FULL (firmware + boot + rootfs)"
fi
echo "[*] Filesystem: ext2/ext4"
echo

# Use files/ directory relative to script location.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
files_dir="$script_dir/files"

if [[ ! -d "$files_dir" ]]; then
    echo "[-] Error: files/ directory not found at: $files_dir"
    echo "[!] Expected structure: script.sh and files/ in the same directory"
    exit 1
fi

echo "[*] Using files directory: $files_dir"
echo

# Detect required images.
echo "[*] Detecting images..."
boot_path=$(find_image "$files_dir" "boot.bin") || exit 1
rootfs_path=$(find_image "$files_dir" "rootfs.bin") || exit 1

echo "[+] Boot: $(basename "$boot_path")"
echo "[+] Rootfs: $(basename "$rootfs_path")"

# Skip firmware detection in lite mode
firmware_tmp=""
firmware_dir=""
gpt_path=""

if [[ "$LITE_MODE" == false ]]; then
    gpt_path=$(find_image "$files_dir" "gpt_both0.bin") || exit 1
    echo "[+] GPT: $(basename "$gpt_path")"
    
    # Detect firmware ZIP and extract .mbn files.
    echo
    echo "=== Firmware bundle (.zip) ==="
    zip_path="$(find_image "$files_dir" "firmware.zip" || true)"

    if [[ -n "${zip_path:-}" ]]; then
        echo "[*] Found firmware ZIP: $(basename "$zip_path")"
        firmware_tmp="$(mktemp -d)"
        trap 'if [[ -n "$firmware_tmp" && -d "$firmware_tmp" ]]; then rm -rf "$firmware_tmp"; fi' EXIT
        echo "[*] Extracting .mbn files..."
        unzip -q -j -d "$firmware_tmp" "$zip_path" "*.mbn" || {
            echo "[-] Error: Failed to extract .mbn files from ZIP"
            exit 1
        }
        firmware_dir="$firmware_tmp"
    else
        echo "[!] No firmware ZIP found in files/"
        echo "=== Qualcomm Firmware Directory (fallback) ==="
        read -e -r -p "Drag the folder with .mbn files (aboot, hyp, rpm, sbl1, tz): " firmware_dir
        firmware_dir="${firmware_dir//\"/}"
        firmware_dir="${firmware_dir//\'/}"
        firmware_dir="${firmware_dir// /}"
    fi

    # Validate firmware directory.
    if [[ -z "$firmware_dir" || ! -d "$firmware_dir" ]]; then
        echo "[-] Error: Invalid firmware directory: $firmware_dir"
        exit 1
    fi

    echo "[*] Using firmware directory: $firmware_dir"
    echo

    # Verify required .mbn files.
    echo "[*] Verifying Qualcomm firmware partitions..."
    missing_mbn=false
    for part in aboot hyp rpm sbl1 tz; do
        if [[ ! -f "$firmware_dir/${part}.mbn" ]]; then
            echo "[-] ${part}.mbn not found"
            missing_mbn=true
        else
            echo "[+] ${part}.mbn"
        fi
    done

    if [[ "$missing_mbn" == true ]]; then
        echo
        echo "[-] ERROR: Missing required .mbn files for flashing."
        exit 1
    fi
fi

# Confirm before flashing.
echo
if [[ "$LITE_MODE" == true ]]; then
    read -p "Continue with LITE flash (boot + rootfs only)? (y/N): " confirm
else
    read -p "Continue with FULL flash? (y/N): " confirm
fi

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "[!] Cancelled"
    exit 0
fi

if [[ "$LITE_MODE" == false ]]; then
    mkdir -p saved

    # Backup critical partitions via EDL.
    echo
    echo "=== Partition Backup (EDL) ==="
    for n in fsc fsg modemst1 modemst2 modem persist sec; do
        echo "[*] Backing up partition $n ..."
        edl r "$n" "saved/$n.bin" || { echo "[-] Error backing up $n"; exit 1; }
    done

    # Flash aboot via EDL to get a known-good aboot.
    echo
    echo "=== Flashing Partitions (EDL) ==="
    echo "[*] Flashing aboot via EDL..."
    edl w aboot "$firmware_dir/aboot.mbn" || { echo "[-] Error flashing aboot"; exit 1; }

    # Reboot to fastboot using EDL commands.
    echo "[*] Rebooting to fastboot..."
    edl e boot || { echo "[-] Error rebooting to fastboot"; exit 1; }
    edl reset || { echo "[-] Error resetting device"; exit 1; }
else
    echo
    echo "=== Waiting for fastboot ==="
    if fastboot devices | grep -qE "fastboot$"; then
        echo "[+] Device already in fastboot"
    elif lsusb | grep -q "05c6:9008"; then
        echo "[*] Device detected in EDL mode — switching to fastboot..."
        edl e boot || { echo "[-] Error booting to fastboot"; exit 1; }
        edl reset  || { echo "[-] Error resetting device"; exit 1; }
    else
        echo "[*] Device not detected — please put it in fastboot mode manually"
    fi
fi

# Wait for fastboot to come up.
echo "[*] Waiting for fastboot mode (up to 30s)..."
for i in {1..30}; do
    if fastboot devices | grep -qE "fastboot$"; then
        echo "[+] Fastboot device detected"
        break
    fi
    sleep 1
    if [[ $i -eq 30 ]]; then
        echo "[-] Error: Fastboot device not detected"
        exit 1
    fi
done

if [[ "$LITE_MODE" == false ]]; then
    # Flash GPT and firmware via fastboot.
    echo
    echo "=== Flashing partitions (fastboot) ==="
    echo "[*] Flashing GPT..."
    fastboot flash partition "$gpt_path" || { echo "[-] Error flashing partition"; exit 1; }

    echo "[*] Flashing firmware (.mbn files)..."
    fastboot flash aboot "$firmware_dir/aboot.mbn" || { echo "[-] Error flashing aboot"; exit 1; }
    fastboot flash hyp   "$firmware_dir/hyp.mbn"   || { echo "[-] Error flashing hyp"; exit 1; }
    fastboot flash rpm   "$firmware_dir/rpm.mbn"   || { echo "[-] Error flashing rpm"; exit 1; }
    fastboot flash sbl1  "$firmware_dir/sbl1.mbn"  || { echo "[-] Error flashing sbl1"; exit 1; }
    fastboot flash tz    "$firmware_dir/tz.mbn"    || { echo "[-] Error flashing tz"; exit 1; }
fi

# Flash boot and rootfs (always, in both modes)
echo
echo "=== Flashing system images (fastboot) ==="
echo "[*] Flashing boot..."
fastboot flash boot "$boot_path" || { echo "[-] Error flashing boot"; exit 1; }
echo "[*] Flashing rootfs..."
fastboot flash rootfs "$rootfs_path" || { echo "[-] Error flashing rootfs"; exit 1; }

if [[ "$LITE_MODE" == false ]]; then
    # Reboot back to EDL to restore radio-cal data partitions.
    echo "[*] Rebooting to EDL mode..."
    fastboot oem reboot-edl || { echo "[-] Error rebooting to EDL"; exit 1; }

    # Small wait for EDL to be available.
    echo "[*] Waiting for EDL mode (3 seconds)..."
    sleep 3

    # Restore backed-up partitions via EDL.
    echo
    echo "=== Partition Restoration (EDL) ==="
    for n in fsc fsg modemst1 modemst2 modem persist sec; do
        echo "[*] Restoring partition $n ..."
        edl w "$n" "saved/$n.bin" || { echo "[-] Error restoring $n"; exit 1; }
    done

    echo
    echo "[+] Process completed successfully"
    echo "[*] Rebooting device..."
    edl reset || { echo "[-] Error resetting device"; exit 1; }
else
    # In lite mode, just reboot from fastboot
    echo
    echo "[+] LITE flash completed successfully"
    echo "[*] Rebooting device..."
    fastboot reboot || { echo "[-] Error rebooting"; exit 1; }
fi

echo "[+] Done!"
