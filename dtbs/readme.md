# Precompiled DTBs

This directory contains precompiled Device Tree Blobs (DTBs) for various MSM8916-based devices.
They serve as a fallback when the build system cannot compile DTS from source.

Built with [`msm8916-openwrt`](https://github.com/kinsamanka/msm8916-openwrt).

## Available DTBs

| File | Device |
|------|--------|
| `msm8916-yiming-uz801v3.dtb` | Yiming UZ801 v3 (default) |
| `msm8916-fy-mf800.dtb` | FY MF800 |
| `msm8916-generic-m9s.dtb` | Generic M9S |
| `msm8916-generic-mf68e.dtb` | Generic MF68E |
| `msm8916-generic-uf02.dtb` | Generic UF02 |
| `msm8916-jz01-45-v33.dtb` | JZ01 45 v33 |

## DTB priority during build

The build system copies DTBs in this order (later copies overwrite earlier ones):

1. `files/dtbs/*.dtb` — compiled from upstream kernel DTS + user `dts/` files by `generate_dts.sh`
2. `dtbs/*.dtb` — precompiled DTBs from this directory (fallback)

## Adding custom device support

Place your custom DTS source files in the `dts/` directory at the project root.
The build system (`generate_dts.sh`) will compile them alongside the upstream DTS files.

Your custom DTS can include files from the upstream kernel tree, for example:

```dts
// dts/msm8916-mydevice.dts
/dts-v1/;
#include "msm8916-ufi.dtsi"
// ... your overrides
```

Run `make dts` to compile only the DTS files, or `make build` to build everything.
