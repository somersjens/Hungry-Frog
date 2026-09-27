#!/usr/bin/env python3
"""Build readable QA contact sheets from the native checkpoint PNGs."""

from pathlib import Path
import sys
from PIL import Image, ImageDraw


def sheet(files: list[Path], destination: Path, title: str) -> None:
    thumbs = []
    for path in files:
        image = Image.open(path).convert("RGB")
        image.thumbnail((480, 300), Image.Resampling.LANCZOS)
        thumbs.append((path, image.copy()))
    if not thumbs:
        return
    columns = 4
    cell_w = 500
    cell_h = 344
    rows = (len(thumbs) + columns - 1) // columns
    canvas = Image.new("RGB", (columns * cell_w, 56 + rows * cell_h), "#f4f8f1")
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 18), title, fill="#276d1d")
    for index, (path, image) in enumerate(thumbs):
        x = (index % columns) * cell_w
        y = 56 + (index // columns) * cell_h
        canvas.paste(image, (x + (cell_w - image.width) // 2, y + 8))
        draw.text((x + 12, y + 316), path.stem.rsplit("-", 1)[-1], fill="#183b14")
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, quality=94)


def main() -> None:
    root = Path(sys.argv[1])
    previews = root / "previews"
    output = root / "contact-sheets"
    for stem in (
        "frog-app-store-teaser-1920x886",
        "frog-app-store-teaser-1600x1200",
    ):
        sheet(sorted(previews.glob(f"{stem}-*.png")),
              output / f"{stem}-checkpoints.jpg",
              f"{stem} — QA checkpoints")


if __name__ == "__main__":
    main()
