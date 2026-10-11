"""Rebuild the SecurePark mark and Android/iOS launch assets with Pillow.

Run from any directory: python mobile-app/tool/generate_brand_assets.py
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


APP = Path(__file__).resolve().parents[1]
NAVY = "#0F265C"
GOLD = "#F5B800"
WHITE = "#FFFFFF"


def font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("C:/Windows/Fonts/arialbd.ttf"),
        Path("C:/Windows/Fonts/Arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    raise FileNotFoundError("A bold TrueType font is required to generate the icon")


def make_mark() -> Image.Image:
    # Draw at 1024 px so every launcher and launch screen variant stays crisp.
    image = Image.new("RGBA", (1024, 1024))
    draw = ImageDraw.Draw(image)
    outer = [
        (512, 91), (754, 175), (794, 193), (794, 476),
        (781, 610), (728, 720), (646, 812), (512, 914),
        (378, 812), (296, 720), (243, 610), (230, 476),
        (230, 193), (270, 175),
    ]
    inner = [
        (512, 151), (730, 225), (737, 231), (737, 475),
        (725, 590), (682, 678), (612, 758), (512, 837),
        (412, 758), (342, 678), (299, 590), (287, 475),
        (287, 231), (294, 225),
    ]
    draw.polygon(outer, fill=GOLD)
    draw.polygon(inner, fill=NAVY)

    # A strong P reads as parking at launcher size; the bar and bollard
    # underneath give the terminal's gate function a second visual cue.
    p_font = font(464)
    bbox = draw.textbbox((0, 0), "P", font=p_font, stroke_width=0)
    width = bbox[2] - bbox[0]
    draw.text((512 - width / 2 - bbox[0], 295 - bbox[1]), "P", font=p_font, fill=WHITE)
    draw.rounded_rectangle((369, 685, 655, 707), radius=11, fill=GOLD)
    draw.rounded_rectangle((393, 708, 411, 752), radius=8, fill=GOLD)
    return image


def save_scaled(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)


def main() -> None:
    mark = make_mark()
    save_scaled(mark, APP / "assets/images/securepark_mark.png", 512)

    icon = Image.new("RGB", (1024, 1024), NAVY)
    icon_mark = mark.resize((856, 856), Image.Resampling.LANCZOS)
    icon.paste(icon_mark, (84, 84), icon_mark)

    res = APP / "android/app/src/main/res"
    for density, size in {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96,
        "xxhdpi": 144, "xxxhdpi": 192,
    }.items():
        save_scaled(icon, res / f"mipmap-{density}/ic_launcher.png", size)
        save_scaled(mark, res / f"mipmap-{density}/launch_mark.png", size * 3)

    assets = APP / "ios/Runner/Assets.xcassets"
    app_icon_dir = assets / "AppIcon.appiconset"
    contents = json.loads((app_icon_dir / "Contents.json").read_text())
    for item in contents["images"]:
        size = round(float(item["size"].split("x")[0]) * int(item["scale"][0]))
        save_scaled(icon, app_icon_dir / item["filename"], size)
    # This file is present in the standard Flutter asset set even though the
    # current Xcode Contents.json does not enumerate it.
    save_scaled(icon, app_icon_dir / "Icon-App-20x20@1x.png", 20)

    launch_dir = assets / "LaunchImage.imageset"
    for scale in (1, 2, 3):
        suffix = "" if scale == 1 else f"@{scale}x"
        save_scaled(mark, launch_dir / f"LaunchImage{suffix}.png", 144 * scale)


if __name__ == "__main__":
    main()
