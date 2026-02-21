builder:
	docker build -t builder .
	docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
	docker run --rm -v ${PWD}:/app -v /tmp:/tmp -w /app -it --privileged builder

dts:
	./scripts/generate_dts.sh ./files

_check-docker:
	@[ -f /.dockerenv ] || { echo "ERROR: Run this target inside the builder container (make builder)"; exit 1; }

clean: _check-docker
	rm -rf files .kernel-dts saved

build: _check-docker
	rm -rf files
	mkdir -p files
	./scripts/generate_dts.sh ./files
	./scripts/generate_alpine_rootfs.sh ./files
	./scripts/generate_images.sh ./files

build-all: build
	./scripts/generate_firmware.sh files/firmware.zip
	./scripts/generate_gpt_table.sh files/gpt_both0.bin
