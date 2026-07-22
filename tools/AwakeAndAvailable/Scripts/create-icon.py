from pathlib import Path
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Assets" / "awake-available.png"
PREVIEW = ROOT / "Assets" / "AwakeAndAvailable-256.png"
OUTPUT = ROOT / "Assets" / "AwakeAndAvailable.ico"
SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)


def prepare_master(source: Image.Image) -> Image.Image:
    rgba = source.convert("RGBA")
    alpha_bounds = rgba.getchannel("A").getbbox()
    if alpha_bounds is None:
        raise RuntimeError("The source image has no visible pixels")

    subject = rgba.crop(alpha_bounds)
    side = max(subject.size)
    padding = max(8, round(side * 0.08))
    canvas_side = side + (padding * 2)
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.alpha_composite(subject, ((canvas_side - subject.width) // 2,
                                     (canvas_side - subject.height) // 2))
    return canvas


def main() -> None:
    with Image.open(SOURCE) as source:
        master = prepare_master(source)

    preview = master.resize((256, 256), Image.Resampling.LANCZOS)
    preview.save(PREVIEW, optimize=True)

    # Pillow stores separate, high-quality bitmap frames for the Windows icon sizes.
    preview.save(OUTPUT, format="ICO", sizes=[(size, size) for size in SIZES])
    print(f"Wrote {OUTPUT}")
    print(f"Wrote {PREVIEW}")


if __name__ == "__main__":
    main()
