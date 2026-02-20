builder:
	docker build -t builder .
	docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
	docker run --rm -v ${PWD}:/app -v /tmp:/tmp -w /app -it --privileged builder

dts:
	./scripts/generate_dts.sh ./files

build:
	# Run inside builder!
	rm -rf files
	mkdir -p files
	./scripts/generate_dts.sh ./files
	./scripts/generate_alpine_rootfs.sh ./files
	./scripts/generate_images.sh ./files
	./scripts/generate_firmware.sh files/firmware.zip
	./scripts/generate_gpt_table.sh files/gpt_both0.bin
