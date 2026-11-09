#!/usr/bin/env bash
# Build boot.rom (hps_io ioctl index 0) from the two 2732 EPROM dumps.
#
#   scripts/make_boot_rom.sh [version] [out]
#     version  1.0 (default), 1.0bc, 2.0d, 2.0f
#     out      default: boot.rom
#   ROMS=<dir> overrides the dump directory
#
# boot.rom format: 8192 bytes, the ROM as the Z8001 sees it at <4>0000.
#   byte 2k   = word k bits 15:8 = "H" EPROM (U54) byte k
#   byte 2k+1 = word k bits 7:0  = "L" EPROM (U65) byte k
# Big-endian Z8001 word order.
set -euo pipefail

ver="${1:-1.0}"
out="${2:-boot.rom}"
roms="${ROMS:-${HOME}/git/olivetti_m20/reference/software/roms}"

case "${ver}" in
  1.0)   hi="Firmware_1_0_zip/Firmware_1_0/hi.bin";    lo="Firmware_1_0_zip/Firmware_1_0/lo.bin"
         sha="d51025e087a94c55529d7ee8fd18ff4c46d93230" ;;
  1.0bc) hi="Firmware_1_0_BC_zip/Firmware_1_0_BC/romPA66.bin"; lo="Firmware_1_0_BC_zip/Firmware_1_0_BC/romPA62.bin"
         sha="" ;;
  2.0d)  hi="Firmware_2_0d_zip/Firmware_2_0d/hi.bin";  lo="Firmware_2_0d_zip/Firmware_2_0d/lo.bin"
         sha="c7cb9d9900b7b5014fcf1ceb2e45a66a91c564d0" ;;
  2.0f)  hi="Firmware_2_0f_zip/Firmware_2_0f/hi.bin";  lo="Firmware_2_0f_zip/Firmware_2_0f/lo.bin"
         sha="149d8513867081d31c73c2965dabb36d5f308041" ;;
  *) echo "make_boot_rom: unknown version ${ver}" >&2; exit 1 ;;
esac

python3 -I - "${roms}/${hi}" "${roms}/${lo}" "${out}" <<'EOF'
import sys
hi = open(sys.argv[1], "rb").read()
lo = open(sys.argv[2], "rb").read()
if len(hi) != 4096 or len(lo) != 4096:
    sys.exit("make_boot_rom: each EPROM dump must be 4096 bytes")
img = bytes(b for pair in zip(hi, lo) for b in pair)
# Header: word 1 FCW 0xC000, words 2-3 PC <4>0150, AAAA 5555 at 0x08,
# "HL" at 0x0E.
w = [img[i] << 8 | img[i + 1] for i in range(0, 16, 2)]
if w[1] != 0xC000 or w[2] != 0x8400 or w[3] != 0x0150 or w[4:6] != [0xAAAA, 0x5555] \
        or w[7] != 0x484C:
    sys.exit("make_boot_rom: header mismatch: " + " ".join(f"{x:04X}" for x in w))
open(sys.argv[3], "wb").write(img)
EOF

if [[ -n "${sha}" ]]; then
  got="$(sha1sum "${out}" | cut -c1-40)"
  [[ "${got}" == "${sha}" ]] || { echo "make_boot_rom: ${out}: SHA1 ${got}, expected ${sha}" >&2; exit 1; }
fi
echo "make_boot_rom: ${out} (ROM ${ver})"
