#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image


def decode_rgb888(raw: bytes, w: int, h: int) -> Image.Image:
    return Image.frombytes("RGB", (w, h), raw, "raw", "RGB")


def decode_rgb565(raw: bytes, w: int, h: int) -> Image.Image:
    # LTDC RGB565 is little-endian: byte0 = low, byte1 = high
    # Pillow "BGR;16" interprets a 16-bit pixel as B:5 G:6 R:5 in LE order,
    # which matches STM32 LTDC RGB565.
    return Image.frombytes("RGB", (w, h), raw, "raw", "BGR;16")


FORMATS = {
    "rgb888": (3, decode_rgb888),
    "rgb565": (2, decode_rgb565),
}


def main() -> int:
    p = argparse.ArgumentParser(description="Convert raw framebuffer dump to PNG")
    p.add_argument("--in", dest="input", required=True, help="Input .bin path")
    p.add_argument("--out", dest="output", required=True, help="Output .png path")
    p.add_argument("--width", type=int, default=604)
    p.add_argument("--height", type=int, default=1024)
    p.add_argument(
        "--format",
        choices=sorted(FORMATS.keys()),
        default="rgb888",
        help="Pixel format: rgb888 (3 B/px) or rgb565 (2 B/px, little-endian). Default: rgb888",
    )
    p.add_argument(
        "--stride",
        type=int,
        default=None,
        help="Bytes per pixel override. If omitted, derived from --format.",
    )
    args = p.parse_args()

    bpp, decoder = FORMATS[args.format]
    if args.stride is not None and args.stride != bpp:
        raise SystemExit(
            f"--stride {args.stride} conflicts with --format {args.format} (expects {bpp})"
        )

    in_path = Path(args.input)
    out_path = Path(args.output)

    if not in_path.exists():
        raise SystemExit(f"input not found: {in_path}")

    need = args.width * args.height * bpp
    data = in_path.read_bytes()
    if len(data) < need:
        raise SystemExit(f"input too small: got {len(data)} bytes, need >= {need}")

    img = decoder(data[:need], args.width, args.height)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print(out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
