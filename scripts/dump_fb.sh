#!/usr/bin/env bash
# One-shot LCD framebuffer dump.
#
# Reads LTDC Layer-1 Current Frame Buffer Address Register (L1CFBAR) over
# SWD to learn which buffer the LCD is currently scanning out, dumps that
# buffer, then converts the raw bytes to a PNG. This avoids the
# double-buffer race that plagued the templated workflow: the old script
# always read a fixed FB_A address, but in LVGL direct mode FB_A may be
# the back buffer (mid-render or one frame stale) while LCD is showing
# FB_B — leading to screenshots that don't match what the user sees.
#
# Usage:
#   dump_fb.sh [out_bin] [out_png]
#
# Override defaults via env vars:
#   DEVICE        J-Link device name           (default: STM32H747XI_M7)
#   SPEED_KHZ    SWD speed in kHz             (default: 12000)
#   WIDTH         pixels                       (default: 604)
#   HEIGHT        pixels                       (default: 1024)
#   FORMAT        rgb565 | rgb888              (default: rgb565)
#   L1CFBAR       LTDC L1 FB-address register  (default: 0x500010AC, STM32H747)

set -euo pipefail

OUT_BIN="${1:-/tmp/fb_dump.bin}"
OUT_PNG="${2:-/tmp/fb_dump.png}"

DEVICE="${DEVICE:-STM32H747XI_M7}"
SPEED_KHZ="${SPEED_KHZ:-12000}"
WIDTH="${WIDTH:-604}"
HEIGHT="${HEIGHT:-1024}"
FORMAT="${FORMAT:-rgb565}"
L1CFBAR="${L1CFBAR:-0x500010AC}"

case "$FORMAT" in
    rgb565) BPP=2 ;;
    rgb888) BPP=3 ;;
    *) echo "ERROR: unknown FORMAT=$FORMAT (rgb565 or rgb888)" >&2; exit 2 ;;
esac
FB_BYTES=$(( WIDTH * HEIGHT * BPP ))
FB_SIZE=$(printf '0x%X' "$FB_BYTES")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECODER="$SCRIPT_DIR/dump_fb.py"

# 1) Probe L1CFBAR to find which buffer the LCD is currently displaying.
PROBE=$(mktemp /tmp/jlink_probe.XXXXXX.jlink)
trap 'rm -f "$PROBE" "$DUMP_SCRIPT"' EXIT
DUMP_SCRIPT=$(mktemp /tmp/jlink_dump.XXXXXX.jlink)

cat > "$PROBE" <<EOF
device $DEVICE
si SWD
speed $SPEED_KHZ
connect
mem32 $L1CFBAR 1
exit
EOF

reg_addr_lower=$(printf '%s' "${L1CFBAR#0x}" | tr 'a-f' 'A-F')
fb_hex=$(JLinkExe -NoGui 1 -CommandFile "$PROBE" 2>&1 \
        | grep -E "^${reg_addr_lower}" | awk '{print $3}' | tr -d '\r')
if [[ -z "$fb_hex" ]]; then
    echo "ERROR: could not parse L1CFBAR ($L1CFBAR)" >&2
    exit 1
fi
FB_ADDR="0x$fb_hex"
echo "LCD front buffer (L1CFBAR=$L1CFBAR): $FB_ADDR"

# 2) Dump exactly that buffer.
cat > "$DUMP_SCRIPT" <<EOF
device $DEVICE
si SWD
speed $SPEED_KHZ
connect
savebin $OUT_BIN,$FB_ADDR,$FB_SIZE
exit
EOF
JLinkExe -NoGui 1 -CommandFile "$DUMP_SCRIPT" > /tmp/jlink_dump_fb.log 2>&1
if [[ ! -s "$OUT_BIN" ]]; then
    echo "ERROR: dump produced empty file; see /tmp/jlink_dump_fb.log" >&2
    tail -20 /tmp/jlink_dump_fb.log >&2 || true
    exit 1
fi
echo "Dumped $(wc -c < "$OUT_BIN") bytes -> $OUT_BIN"

# 3) Decode raw bytes to PNG.
python3 "$DECODER" \
    --in "$OUT_BIN" --out "$OUT_PNG" \
    --width "$WIDTH" --height "$HEIGHT" --format "$FORMAT"
echo "PNG: $OUT_PNG"
