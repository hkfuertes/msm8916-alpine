builder:
	vagrant up
	vagrant rsync
	vagrant ssh -c "cd /app && sudo bash"

fetch:
	@mkdir -p files
	vagrant ssh -c "cd /app/files && tar cf - *.img.gz *.zip *.bin dtbs/ 2>/dev/null" | tar xf - -C files/
	@echo "[+] Fetched to files/:"
	@ls -lh files/

dts:
	./scripts/generate_dts.sh ./files

_check-env:
	@systemd-detect-virt -q 2>/dev/null || [ -f /proc/1/cgroup ] || { echo "ERROR: Run this inside the builder VM (make builder) or a CI environment"; exit 1; }

clean: _check-env
	rm -rf files .kernel-dts saved

build: _check-env
	rm -rf files
	mkdir -p files
	./scripts/generate_dts.sh ./files
	./scripts/generate_alpine_rootfs.sh ./files
	./scripts/generate_images.sh ./files

build-all: build
	./scripts/generate_firmware.sh files/firmware.zip
	./scripts/generate_gpt_table.sh files/gpt_both0.bin
