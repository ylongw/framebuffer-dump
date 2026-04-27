# framebuffer-dump

Dump the current STM32 LCD framebuffer via J-Link and convert it to a PNG image — useful for pixel-perfect comparison with Figma designs or regression snapshots.

## How it works

1. Reads `LTDC_L1CFBAR` over SWD to find which framebuffer the LCD is **currently** scanning out
2. Dumps that buffer from SDRAM (e.g. `0xD0000000` or `0xD0200000` on PRO2)
3. Converts the raw binary to PNG using `dump_fb.py`

Step 1 is what makes the screenshot match what's actually on the LCD. With double-buffered LVGL direct mode, a hardcoded address may point to the back buffer (mid-render or stale) — reading L1CFBAR avoids that race.

## Requirements

- [SEGGER J-Link](https://www.segger.com/downloads/jlink/) (`JLinkExe` in PATH)
- Python 3.8+ with [Pillow](https://pypi.org/project/Pillow/): `pip install Pillow`

## Usage

```bash
scripts/dump_fb.sh /tmp/fb_dump.bin /tmp/fb_dump.png
```

Defaults target STM32H747 PRO2 (604×1024, RGB565). Override via env vars:

| Var | Default | Notes |
|---|---|---|
| `DEVICE` | `STM32H747XI_M7` | J-Link device name |
| `SPEED_KHZ` | `12000` | SWD speed |
| `WIDTH` | `604` | pixels |
| `HEIGHT` | `1024` | pixels |
| `FORMAT` | `rgb565` | `rgb565` or `rgb888` |
| `L1CFBAR` | `0x500010AC` | LTDC L1 FB-address register |

```bash
# Example: PRO1 (480×800) RGB888
FORMAT=rgb888 WIDTH=480 HEIGHT=800 scripts/dump_fb.sh /tmp/pro1.bin /tmp/pro1.png
```

For non-LTDC targets, see `SKILL.md` for the manual `JLinkExe` + template workflow.

## Default parameters (STM32H747 PRO2)

| Parameter | Value |
|---|---|
| FB candidates | `0xD0000000` (FB_A), `0xD0200000` (FB_B) — wrapper picks via L1CFBAR |
| Resolution | 604 × 1024 |
| Pixel format | RGB565 (2 bytes/pixel) |
| Dump size | `0x12E000` (1,236,992 bytes) |

Adapt these to match your target's display configuration via env vars or the manual workflow.

## Troubleshooting

- **Output .bin is 0 bytes** — check J-Link connection and path permissions
- **Colors look wrong** — verify pixel format (RGB888 vs BGR888 vs RGB565)
- **Image shifted or corrupt** — verify width/height match current display mode
- **Overlays clipped / content stale even though device looks fine** — you're reading a back buffer; use `dump_fb.sh` (which auto-selects via L1CFBAR) instead of a hardcoded address

## OpenClaw skill

If you use [OpenClaw](https://openclaw.ai), install this as an agent skill:

```
/skill install framebuffer-dump
```

The agent will handle the full workflow automatically.

## License

MIT
