---
name: framebuffer-dump
description: Dump the current STM32 LCD framebuffer via J-Link and convert it to PNG for visual comparison with Figma. Auto-detects the front buffer by reading LTDC L1CFBAR so the screenshot matches what the LCD is actually showing (works correctly with double-buffered LVGL direct mode). Supports RGB888 and RGB565 — pick the one matching the target's LTDC configuration (PRO2 currently uses RGB565). Use when user asks to export, snapshot, dump, or capture what is currently displayed on device screen.
---

# Framebuffer Dump (J-Link → PNG)

Export the **actual on-device rendered frame** directly from SDRAM framebuffer and convert to PNG.

## One-shot workflow (recommended)

```bash
scripts/dump_fb.sh /tmp/fb_dump.bin /tmp/fb_dump.png
```

This wrapper:
1. Reads `LTDC_L1CFBAR` (`0x500010AC` on STM32H747) over SWD to find which framebuffer the LCD is currently scanning out
2. Dumps **that** buffer (not a hardcoded address)
3. Converts the raw bytes to PNG via `dump_fb.py`

Defaults target PRO2 (`STM32H747XI_M7`, 604×1024, RGB565). Override with env vars:

| Var | Default | Notes |
|---|---|---|
| `DEVICE` | `STM32H747XI_M7` | J-Link device name |
| `SPEED_KHZ` | `12000` | SWD speed |
| `WIDTH` | `604` | pixels |
| `HEIGHT` | `1024` | pixels |
| `FORMAT` | `rgb565` | `rgb565` or `rgb888` |
| `L1CFBAR` | `0x500010AC` | LTDC L1 FB-address register |

```bash
# Example: PRO1 RGB888
FORMAT=rgb888 WIDTH=480 HEIGHT=800 scripts/dump_fb.sh /tmp/pro1.bin /tmp/pro1.png
```

## Why auto-detect L1CFBAR?

PRO2 runs LVGL direct mode with two framebuffers:
- `0xD0000000` (FB_A)
- `0xD0200000` (FB_B, FB_A + 2MB)

LVGL alternates: render to back buffer → swap → repeat. At any moment the LCD scans out **one** of the two. If the dump always reads a hardcoded address (the old workflow read FB_A), it may be reading the back buffer — which can be mid-render or one frame stale relative to the LCD. Symptoms: pills/overlays clipped, content reverts to a previous state, partial redraws look broken even though the device looks fine.

`LTDC_L1CFBAR` always holds the address the LCD is currently scanning out, so reading it first guarantees the dump matches the LCD.

## Pixel formats

Pick the format matching the target's LTDC configuration. If you don't know, read `LTDC_L1CFBLR` pitch (bits 28:16) and divide by width:
- pitch / width = 2 → RGB565
- pitch / width = 3 → RGB888

| Format | Bytes/px | Dump size (604×1024) |
|---|---|---|
| `rgb888` | 3 | `0x1C5000` (1,855,488) |
| `rgb565` | 2 | `0x12E000` (1,236,992) |

## Manual workflow (advanced / non-LTDC targets)

If you can't use the auto-detect wrapper (e.g. non-STM32 LTDC, or you want to dump a specific buffer):

### 1) Create J-Link command file
Use `scripts/dump_fb.jlink.template` and replace placeholders:
- `{{DEVICE}}` (e.g. `STM32H747XI_M7`)
- `{{SPEED_KHZ}}` (e.g. `12000`)
- `{{OUT_BIN}}` (absolute path)
- `{{FB_ADDR}}` (e.g. `0xD0000000`)
- `{{FB_SIZE}}` — **must match format**: `0x12E000` for RGB565, `0x1C5000` for RGB888

### 2) Dump raw framebuffer
```bash
JLinkExe -NoGui 1 -CommandFile /tmp/jlink_dump_fb.jlink > /tmp/jlink_dump_fb.log 2>&1
```

### 3) Convert raw to PNG
```bash
# RGB565 (PRO2 default)
python3 scripts/dump_fb.py \
  --in /tmp/fb_dump.bin \
  --out /tmp/fb_dump.png \
  --width 604 --height 1024 --format rgb565

# RGB888
python3 scripts/dump_fb.py \
  --in /tmp/fb_dump.bin \
  --out /tmp/fb_dump.png \
  --width 604 --height 1024 --format rgb888
```

`--format` selects bytes-per-pixel and decoder automatically; no need to pass `--stride`.

## Verifying format / framebuffer addresses on unknown firmware

Before dumping, you can read the LTDC layer-1 config registers directly:

```bash
cat > /tmp/jlink_ltdc.jlink <<'EOF'
device STM32H747XI_M7
si SWD
speed 12000
connect
mem32 0x500010AC 1   # LTDC_L1CFBAR — currently displayed framebuffer base
mem32 0x500010B0 1   # LTDC_L1CFBLR — pitch (bits 28:16) and line length (bits 12:0)
exit
EOF
JLinkExe -NoGui 1 -CommandFile /tmp/jlink_ltdc.jlink
```

`pitch / width` gives bytes/pixel (2 = RGB565, 3 = RGB888).

## Troubleshooting
- If output bin is 0 bytes: check J-Link connection / path permissions.
- If image is stretched vertically and the bottom half is noise: **wrong pixel format** — you likely dumped RGB565 FB as RGB888 (or vice versa). Re-check the LTDC pitch register.
- If colors look wrong (tinted / swapped): byte order mismatch. RGB565 decoder expects little-endian (LTDC native). For RGB888, verify channel order.
- If image shifted/corrupt: verify width/height match current display mode.
- If overlays appear clipped or content seems stale even though device looks fine: you're using the manual workflow with a hardcoded FB address that matches the back buffer. Use `dump_fb.sh` instead.
- If command hangs too long: make sure dump size matches the format.

## Notes
- This method captures **real framebuffer pixels** (no camera distortion).
- Best for Figma-vs-device pixel comparison and regression snapshots.
- The wrapper `dump_fb.sh` is self-contained — invoke it directly without expanding templates.
