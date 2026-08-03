"""Composes the launcher icon: iFarmer logo + small red "Grain Collector"
text beneath it. Run after changing assets/images/logo.png, then re-run
`dart run flutter_launcher_icons` to regenerate the actual mipmaps.
"""

from PIL import Image, ImageDraw, ImageFont

SOURCE_LOGO = "assets/images/logo.png"
OUTPUT_ICON = "assets/images/app_icon.png"
FONT_PATH = "C:/Windows/Fonts/arialbd.ttf"

CANVAS_SIZE = 1024
LOGO_SIZE = 620
TEXT = "Grain Collector"
TEXT_COLOR = (200, 20, 20, 255)
FONT_SIZE = 56

canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (255, 255, 255, 255))

logo = Image.open(SOURCE_LOGO).convert("RGBA")
logo = logo.resize((LOGO_SIZE, LOGO_SIZE), Image.LANCZOS)
logo_x = (CANVAS_SIZE - LOGO_SIZE) // 2
logo_y = 140
canvas.paste(logo, (logo_x, logo_y), logo)

draw = ImageDraw.Draw(canvas)
font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
bbox = draw.textbbox((0, 0), TEXT, font=font)
text_w = bbox[2] - bbox[0]
text_x = (CANVAS_SIZE - text_w) // 2
text_y = logo_y + LOGO_SIZE + 20
draw.text((text_x, text_y), TEXT, font=font, fill=TEXT_COLOR)

canvas.save(OUTPUT_ICON)
print(f"Wrote {OUTPUT_ICON}")
