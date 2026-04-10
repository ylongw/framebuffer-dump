---
name: framebuffer-dump
description: Dump the current STM32 LCD framebuffer via J-Link and convert it to PNG for visual comparison with Figma. Supports RGB888 and RGB565 pixel formats — pick the one matching the target's LTDC configuration (PRO2 currently uses RGB565). Use when user asks to export, snapshot, dump, or capture what is currently displayed on device screen.
---

# Framebuffer Dump (J-Link → PNG)

Export the **actual on-device rendered frame** directly from SDRAM framebuffer and convert to PNG.

## Pixel formats

Pick the format matching the target's LTDC configuration. If you don't know, read `LTDC_L1CFBLR` pitch (bits 28:16) and divide by width:
- pitch / width = 2 → RGB565
- pitch / width = 3 → RGB888

| Format | Bytes/px | Dump size (604x1024) |
|---|---|---|
| `rgb888` | 3 | `0x1C5000` (1,855,488) |
| `rgb565` | 2 | `0x12E000` (1,236,992) |

## Default parameters (PRO2, current firmware)
- Device: `STM32H747XI_M7`
- FB base: `0xD0000000`
- Resolution: `604x1024`
- **Pixel format: `RGB565`** (little-endian, LTDC native)
- Dump size: `604*1024*2 = 1,236,992 (0x12E000)`

Other targets (e.g. PRO1 or RGB888 builds) use different values — verify by reading the LTDC registers.

## One-shot workflow

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

## Verifying the format on unknown firmware

Before dumping, you can read the LTDC layer-1 config registers to confirm FB address and pitch:

```bash
cat > /tmp/jlink_ltdc.jlink <<'EOF'
device STM32H747XI_M7
si SWD
speed 12000
connect
mem32 0x500010AC 1   # LTDC_L1CFBAR — framebuffer base
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
- If command hangs too long: make sure dump size matches the format.

## Notes
- This method captures **real framebuffer pixels** (no camera distortion).
- Best for Figma-vs-device pixel comparison and regression snapshots.
- With double-buffered LVGL direct mode, `0xD0000000` is FB_A and `0xD0000000 + 2MB` is FB_B; dump both if the front buffer is ambiguous.
