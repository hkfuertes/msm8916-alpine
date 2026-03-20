#!/usr/bin/env bash
# Flash Alpine Linux to MSM8916 devices entirely via EDL.
# Prerequisites: edl (pip install edl)
# Usage:
#   ./flash.sh         - Full flash (firmware + GPT + boot + rootfs)
#   ./flash.sh -l      - Lite flash (only boot + rootfs)

set -euo pipefail

# Must match TOT_SECTORS in generate_gpt_table.sh
TOT_SECTORS=7634944

# Parse arguments
LITE_MODE=false
while getopts "l" opt; do
    case $opt in
        l) LITE_MODE=true ;;
        *)
            echo "Usage: $0 [-l]"
            echo "  -l    Lite mode: Only flash boot and rootfs (skip firmware and GPT)"
            exit 1
            ;;
    esac
done

# Temp files - cleaned up on exit
firmware_tmp=""
gpt_tmp=""
raw_tmp=""
trap 'rm -rf "$firmware_tmp" "$gpt_tmp" "$raw_tmp"' EXIT

find_image() {
    local dir="$1" pattern="$2" file
    file=$(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | head -n 1 || true)
    if [[ -z "${file:-}" ]]; then
        echo "[-] Error: Image not found: $pattern" >&2
        return 1
    fi
    echo "$file"
}

echo "=== Alpine Linux MSM8916 EDL Flash Script ==="
if [[ "$LITE_MODE" == true ]]; then
    echo "[*] Mode: LITE (boot + rootfs only)"
else
    echo "[*] Mode: FULL (firmware + GPT + boot + rootfs)"
fi
echo

# Use files/ directory relative to script location.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
files_dir="$script_dir/files"

if [[ ! -d "$files_dir" ]]; then
    echo "[-] Error: files/ directory not found at: $files_dir"
    exit 1
fi

# Detect required images.
echo "[*] Detecting images..."
boot_path=$(find_image "$files_dir" "boot.img.gz") || exit 1
rootfs_path=$(find_image "$files_dir" "rootfs.img.gz") || exit 1

echo "[+] Boot:   $(basename "$boot_path")"
echo "[+] Rootfs: $(basename "$rootfs_path")"

firmware_dir=""
gpt_path=""

if [[ "$LITE_MODE" == false ]]; then
    gpt_path=$(find_image "$files_dir" "gpt_both0.bin") || exit 1
    echo "[+] GPT:    $(basename "$gpt_path")"

    # Detect firmware ZIP and extract .mbn files.
    echo
    echo "=== Firmware bundle (.zip) ==="
    zip_path="$(find_image "$files_dir" "firmware.zip" || true)"

    if [[ -n "${zip_path:-}" ]]; then
        echo "[*] Found firmware ZIP: $(basename "$zip_path")"
        firmware_tmp="$(mktemp -d)"
        echo "[*] Extracting .mbn files..."
        unzip -q -j -d "$firmware_tmp" "$zip_path" "*.mbn" || {
            echo "[-] Error: Failed to extract .mbn files from ZIP"
            exit 1
        }
        firmware_dir="$firmware_tmp"
    else
        echo "[!] No firmware ZIP found in files/"
        read -e -r -p "Drag the folder with .mbn files (aboot, hyp, rpm, sbl1, tz): " firmware_dir
        firmware_dir="${firmware_dir//\"/}"
        firmware_dir="${firmware_dir//\'/}"
        firmware_dir="${firmware_dir// /}"
    fi

    if [[ -z "$firmware_dir" || ! -d "$firmware_dir" ]]; then
        echo "[-] Error: Invalid firmware directory: $firmware_dir"
        exit 1
    fi

    # Verify required .mbn files.
    echo "[*] Verifying firmware partitions..."
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
        echo "[-] ERROR: Missing required .mbn files."
        exit 1
    fi
fi

# Confirm before flashing.
echo
read -r -p "Continue with flashing? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "[!] Cancelled"
    exit 0
fi

mkdir -p saved

# Backup critical partitions.
echo
echo "=== Partition Backup (EDL) ==="
for n in fsc fsg modemst1 modemst2 modem persist sec; do
    echo "[*] Backing up $n..."
    edl r "$n" "saved/$n.bin" || { echo "[-] Error backing up $n"; exit 1; }
done

if [[ "$LITE_MODE" == false ]]; then
    # Flash GPT via raw sector writes.
    # gpt_both0.bin layout: [34 sectors primary] [32 sectors backup entries] [1 sector backup header]
    echo
    echo "=== Flashing GPT (EDL) ==="
    gpt_tmp="$(mktemp -d)"
    dd if="$gpt_path" bs=512 count=34         of="${gpt_tmp}/primary.bin"        2>/dev/null
    dd if="$gpt_path" bs=512 skip=34 count=32 of="${gpt_tmp}/backup_entries.bin" 2>/dev/null
    dd if="$gpt_path" bs=512 skip=66 count=1  of="${gpt_tmp}/backup_header.bin"  2>/dev/null
    edl ws 0                       "${gpt_tmp}/primary.bin"        || { echo "[-] Error flashing primary GPT"; exit 1; }
    edl ws $((TOT_SECTORS - 33))  "${gpt_tmp}/backup_entries.bin" || { echo "[-] Error flashing GPT backup entries"; exit 1; }
    edl ws $((TOT_SECTORS - 1))   "${gpt_tmp}/backup_header.bin"  || { echo "[-] Error flashing GPT backup header"; exit 1; }

    # Flash firmware.
    echo
    echo "=== Flashing Firmware (EDL) ==="
    edl w aboot "$firmware_dir/aboot.mbn" || { echo "[-] Error flashing aboot"; exit 1; }
    edl w hyp   "$firmware_dir/hyp.mbn"   || { echo "[-] Error flashing hyp";   exit 1; }
    edl w rpm   "$firmware_dir/rpm.mbn"   || { echo "[-] Error flashing rpm";   exit 1; }
    edl w sbl1  "$firmware_dir/sbl1.mbn"  || { echo "[-] Error flashing sbl1";  exit 1; }
    edl w tz    "$firmware_dir/tz.mbn"    || { echo "[-] Error flashing tz";    exit 1; }
fi

# Decompress images for EDL.
echo
echo "=== Decompressing images ==="
raw_tmp="$(mktemp -d)"
echo "[*] Decompressing boot..."
gunzip -c "$boot_path" > "${raw_tmp}/boot.raw"
echo "[*] Decompressing rootfs..."
gunzip -c "$rootfs_path" > "${raw_tmp}/rootfs.raw"

# Flash boot and rootfs (always, in both modes).
echo
echo "=== Flashing System Images (EDL) ==="
edl w boot   "${raw_tmp}/boot.raw"   || { echo "[-] Error flashing boot";   exit 1; }
edl w rootfs "${raw_tmp}/rootfs.raw" || { echo "[-] Error flashing rootfs"; exit 1; }

# Restore radio partitions.
echo
echo "=== Partition Restoration (EDL) ==="
for n in fsc fsg modemst1 modemst2 modem persist sec; do
    echo "[*] Restoring $n..."
    edl w "$n" "saved/$n.bin" || { echo "[-] Error restoring $n"; exit 1; }
done

echo
echo "[+] Flash completed successfully"
echo "[*] Rebooting..."
edl reset || { echo "[-] Error resetting device"; exit 1; }
