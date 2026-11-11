#!/usr/bin/env bash
# Build apb.rom (hps_io ioctl index 0x40 = boot1.rom, or Load APB ROM) for
# the APB 1086 card.
#
#   scripts/make_apb_rom.sh [out] [rom]
#     out   default: boot1.rom
#     rom   16 KB 8086 image as seen at FC000, default apb-1086-2.0.bin
#   ROMS=<dir>    overrides the firmware86 dump directory
#   UCODE=<file>  8086 microcode (z8086 ucode.hex); fetched if unset
#
# apb.rom format: 18432 bytes.
#   0000-3FFF  8086 ROM (even bytes U11, odd bytes U12)
#   4000-47FF  microcode, 512 words, 4 bytes each, little endian
set -euo pipefail

out="${1:-boot1.rom}"
roms="${ROMS:-${HOME}/git/olivetti_m20/reference/hardware/firmware/firmware86/firmware86}"
rom="${2:-${roms}/apb-1086-2.0.bin}"
uc_url="https://raw.githubusercontent.com/nand2mario/z8086/596d9a6616b90c31f35b0d0947d4c1b11aa7a674/src/z8086/ucode.hex"
uc_sha="baf40ef0b3f08c1696f42a2dcb8d37087750a5f2"

ucode="${UCODE:-}"
tmp=""
if [[ -z "${ucode}" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  ucode="${tmp}/ucode.hex"
  curl -fsSL -o "${ucode}" "${uc_url}"
fi
got="$(sha1sum "${ucode}" | cut -c1-40)"
[[ "${got}" == "${uc_sha}" ]] || { echo "make_apb_rom: ${ucode}: SHA1 ${got}, expected ${uc_sha}" >&2; exit 1; }

python3 -I - "${rom}" "${ucode}" "${out}" <<'EOF'
import sys
rom = open(sys.argv[1], "rb").read()
if len(rom) != 16384:
    sys.exit("make_apb_rom: the 8086 ROM must be 16384 bytes")
words = [int(l, 16) for l in open(sys.argv[2]) if l.strip()]
if len(words) != 512:
    sys.exit("make_apb_rom: the microcode must be 512 words")
uc = b"".join((w & 0x1FFFFF).to_bytes(4, "little") for w in words)
open(sys.argv[3], "wb").write(rom + uc)
EOF
echo "make_apb_rom: ${out}"
