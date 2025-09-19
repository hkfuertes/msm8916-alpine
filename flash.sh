#!/usr/bin/env bash
# Prerequisites: EDL mode.

rm -rf saved && mkdir saved
# Backup important partitions
for n in fsc fsg modem modemst1 modemst2 persist sec; do
    echo "Backing up partition $n ..."
    edl r "$n" "saved/$n.bin" || { echo "Error backing up $n"; exit 1; }
done

# Install `aboot`
echo "Flashing aboot..."
edl w aboot aboot.mbn || { echo "Error flashing aboot"; exit 1; }

# Reboot to fastboot
echo "Rebooting to fastboot..."
edl e boot || { echo "Error rebooting to fastboot"; exit 1; }
edl reset || { echo "Error resetting device"; exit 1; }

# Flash firmware
echo "Flashing partitions..."
fastboot flash partition gpt_both0.bin || { echo "Error flashing partition"; exit 1; }
fastboot flash aboot aboot.mbn || { echo "Error flashing aboot"; exit 1; }
fastboot flash hyp hyp.mbn || { echo "Error flashing hyp"; exit 1; }
fastboot flash rpm rpm.mbn || { echo "Error flashing rpm"; exit 1; }
fastboot flash sbl1 sbl1.mbn || { echo "Error flashing sbl1"; exit 1; }
fastboot flash tz tz.mbn || { echo "Error flashing tz"; exit 1; }

fastboot flash boot boot.bin || { echo "Error flashing boot"; exit 1; }

fastboot flash rootfs alpine_rootfs.bin || { echo "Error flashing rootfs"; exit 1; }

echo "Rebooting to EDL mode..."
fastboot oem reboot-edl || { echo "Error rebooting to EDL"; exit 1; }

# Restore original partitions
for n in fsc fsg modem modemst1 modemst2 persist sec; do
    echo "Restoring partition $n ..."
    edl w "$n" "saved/$n.bin" || { echo "Error restoring $n"; exit 1; }
done

echo "Process completed successfully."
