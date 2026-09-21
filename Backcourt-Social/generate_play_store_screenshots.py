#!/usr/bin/env python3
"""Generate Korean Google Play phone screenshots from current Android captures."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
SOURCE_DIR = ROOT / "assets" / "play-store-screens"
EXPORT_DIR = ROOT / "exports" / "play-store"

WIDTH = 1080
HEIGHT = 1920
ORANGE = "#FF613F"
BLACK = "#090909"
WHITE = "#FFFFFF"

FONT_PATH = Path("/System/Library/Fonts/AppleSDGothicNeo.ttc")

SCREENS = (
    ("map.png", "screenshot-01-courts.png", "코트 찾기"),
    ("court-detail.png", "screenshot-02-court-detail.png", "코트 정보"),
    ("live.png", "screenshot-03-live.png", "지금, LIVE"),
    ("checkin.png", "screenshot-04-checkin.png", "GPS 출석"),
)


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=255)
    output = Image.new("RGBA", image.size)
    output.paste(image.convert("RGBA"), mask=mask)
    return output


def render(source_name: str, output_name: str, title: str) -> None:
    source = Image.open(SOURCE_DIR / source_name).convert("RGB")
    canvas = Image.new("RGB", (WIDTH, HEIGHT), ORANGE)
    draw = ImageDraw.Draw(canvas)

    brand_font = ImageFont.truetype(str(FONT_PATH), 30, index=8)
    title_font = ImageFont.truetype(str(FONT_PATH), 68, index=8)
    draw.text((72, 50), "BACKCOURT", font=brand_font, fill=BLACK)
    draw.text((68, 91), title, font=title_font, fill=WHITE)

    screen_width = 760
    screen_height = round(source.height * screen_width / source.width)
    source = source.resize((screen_width, screen_height), Image.Resampling.LANCZOS)
    source = rounded_image(source, 42)

    x = (WIDTH - screen_width) // 2
    y = 190
    shadow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x + 18, y + 24, x + screen_width + 18, y + screen_height + 24),
        radius=44,
        fill=(63, 23, 15, 105),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    canvas.alpha_composite(source, (x, y))
    canvas.convert("RGB").save(EXPORT_DIR / output_name, quality=95)


def main() -> None:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    for screen in SCREENS:
        render(*screen)


if __name__ == "__main__":
    main()
