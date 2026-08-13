from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Assets"
ACTIVE_SOURCE = ASSETS / "bird-active-source.png"
INACTIVE_SOURCE = ASSETS / "bird-inactive-source.png"
SIZES = (16, 20, 24, 32, 48, 64, 128, 256)


def fitted(source: Image.Image, size: int) -> Image.Image:
    image = source.convert("RGBA")
    bounds = image.getchannel("A").point(lambda value: 255 if value > 8 else 0).getbbox()
    if bounds is None:
        raise RuntimeError("The source image has no visible pixels")
    image = image.crop(bounds)
    padding = max(1, round(size * 0.07))
    available = size - padding * 2
    scale = min(available / image.width, available / image.height)
    rendered = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(rendered, ((size - rendered.width) // 2, (size - rendered.height) // 2))
    return canvas

def build(source_path: Path, stem: str) -> list[Image.Image]:
    source = Image.open(source_path)
    frames = [fitted(source, size) for size in SIZES]
    frames[-1].save(ASSETS / f"{stem}-256.png", optimize=True)
    frames[-1].save(ASSETS / f"{stem}.ico", format="ICO", append_images=frames[:-1], sizes=[(size, size) for size in SIZES])
    return frames

def main() -> None:
    active = build(ACTIVE_SOURCE, "AwakeAndAvailable")
    inactive = build(INACTIVE_SOURCE, "AwakeAndAvailable-Inactive")
    active[-1].save(ASSETS / "awake-available.png", optimize=True)
    preview = Image.new("RGBA", (430, 140), "#f4f5f7")
    draw = ImageDraw.Draw(preview)
    draw.text((18, 12), "Actual-size tray previews on a dark menu bar", fill="#22262d")
    for row, (label, frames) in enumerate((("ACTIVE", active), ("INACTIVE", inactive))):
        y = 40 + row * 46
        draw.text((18, y + 9), label, fill="#30343b")
        x = 100
        for size in (16, 20, 24, 32):
            draw.rectangle((x, y, x + 38, y + 38), fill="#20242c")
            icon = frames[SIZES.index(size)]
            preview.alpha_composite(icon, (x + (38 - size) // 2, y + (38 - size) // 2))
            draw.text((x + 11, y + 39), str(size), fill="#30343b")
            x += 72
    preview.save(ASSETS / "AwakeAndAvailable-tray-preview.png", optimize=True)
    print("Wrote active/inactive PNG, ICO, and tray preview assets")


if __name__ == "__main__":
    main()
