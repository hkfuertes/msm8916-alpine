#!/bin/sh -e

# echo "Install dependencies\n"
# scripts/install_deps.sh

echo "\nBuild hyp and aboot firmware\n"
scripts/build_hyp_aboot.sh

echo "\nExtract MSM8916 firmware\n"
scripts/extract_fw.sh

echo "\nCreate rootfs\n"
scripts/alpine_rootfs.sh

echo "\nCreate images\n"
scripts/build_images.sh

echo "\nCopying flasher\n"
cp ./flash.sh files

echo "\nChanging permissions on files folder\n"
chmod 777 -R files
