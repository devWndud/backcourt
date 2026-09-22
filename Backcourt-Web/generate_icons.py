#!/usr/bin/env python3
"""Generate website icons from the full-size circular Backcourt mark."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "assets" / "icon.png"
BACKGROUND = (11, 11, 11, 255)


def render(size: int, filename: str, *, opaque: bool = False) -> None:
    logo = Image.open(SOURCE).convert("RGBA")
    logo = logo.resize((size, size), Image.Resampling.LANCZOS)
    output = Image.new(
        "RGBA",
        (size, size),
        BACKGROUND if opaque else (0, 0, 0, 0),
    )
    output.alpha_composite(logo)
    if opaque:
        output = output.convert("RGB")
    output.save(ROOT / filename, optimize=True)


def main() -> None:
    render(96, "favicon.png")
    render(192, "icon-192.png")
    render(180, "apple-touch-icon.png", opaque=True)


if __name__ == "__main__":
    main()
