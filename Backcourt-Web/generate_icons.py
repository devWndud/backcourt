#!/usr/bin/env python3
"""Generate opaque website icons so search engines do not add a white halo."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "assets" / "icon.png"
BACKGROUND = (11, 11, 11, 255)


def render(size: int, filename: str) -> None:
    logo = Image.open(SOURCE).convert("RGBA")
    logo = logo.resize((size, size), Image.Resampling.LANCZOS)
    output = Image.new("RGBA", (size, size), BACKGROUND)
    output.alpha_composite(logo)
    output.convert("RGB").save(ROOT / filename, optimize=True)


def main() -> None:
    render(96, "favicon.png")
    render(192, "icon-192.png")
    render(180, "apple-touch-icon.png")


if __name__ == "__main__":
    main()
