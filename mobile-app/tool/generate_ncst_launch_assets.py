"""Build the NCST seal badge used on the launch screen and the sign-in header.

The seal (web-app-admin/assets/ncst-emblem.png) has dark navy ribbon ends that disappear on the app's navy
launch background, so it is placed on a white disc. The disc is 160 dp everywhere (native launch bitmap,
Android 12 system splash icon, first Flutter frame) so the hand-off between them does not jump in size.

Run from any directory: python mobile-app/tool/generate_ncst_launch_assets.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

APP = Path(__file__).resolve().parents[1]
EMBLEM = APP.parent / "web-app-admin" / "assets" / "ncst-emblem.png"
RES = APP / "android" / "app" / "src" / "main" / "res"

DISC_DP = 160          # visible badge diameter, identical in every launch stage
SPLASH_CANVAS_DP = 288  # Android 12 splash icon canvas (no icon background): 288 dp, masked to a 192 dp circle
FILL = 0.80            # share of the disc radius the seal's bounding circle may use


def badge(diameter: int) -> Image.Image:
    """A white disc of `diameter` px with the NCST seal centred inside it (supersampled for smooth edges)."""
    scale = 4
    d = diameter * scale
    emblem = Image.open(EMBLEM).convert("RGBA")
    alpha = emblem.getchannel("A")
    box = alpha.point(lambda a: 255 if a > 40 else 0).getbbox()
    emblem = emblem.crop(box)
    w, h = emblem.size
    # Radius of the circle around the seal's centre that contains every visible pixel
    mask = emblem.getchannel("A").point(lambda a: 255 if a > 40 else 0)
    px = mask.load()
    cx, cy = w / 2, h / 2
    r = max(
        ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
        for y in range(h)
        for x in range(w)
        if px[x, y]
    )
    k = FILL * (d / 2) / r
    emblem = emblem.resize((round(w * k), round(h * k)), Image.LANCZOS)

    img = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse([0, 0, d - 1, d - 1], fill=(255, 255, 255, 255))
    img.alpha_composite(emblem, ((d - emblem.width) // 2, (d - emblem.height) // 2))
    return img.resize((diameter, diameter), Image.LANCZOS)


def main() -> None:
    # Flutter asset: used by the launch screen and the sign-in header at any size
    out = APP / "assets" / "images" / "ncst_mark.png"
    badge(1024).save(out, optimize=True)
    print("wrote", out.relative_to(APP))

    # Native launch bitmap (Android < 12, and the window background behind the Flutter view): 160 dp per density
    for folder, density in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
        out = RES / f"mipmap-{folder}" / "launch_mark.png"
        badge(round(DISC_DP * density)).save(out, optimize=True)
        print("wrote", out.relative_to(APP))

    # Android 12+ system splash icon: 288 dp canvas with the 160 dp disc centred (inside the 192 dp mask circle)
    px = 1152  # 288 dp at 4x; the system scales it, so one density-independent file is enough
    disc = badge(round(px * DISC_DP / SPLASH_CANVAS_DP))
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    canvas.alpha_composite(disc, ((px - disc.width) // 2, (px - disc.height) // 2))
    folder = RES / "drawable-nodpi"
    folder.mkdir(exist_ok=True)
    out = folder / "splash_icon.png"
    canvas.save(out, optimize=True)
    print("wrote", out.relative_to(APP))


if __name__ == "__main__":
    main()
