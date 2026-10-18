#!/usr/bin/env python3
"""Regenerate the Mac icon from the committed PNG master (requires Pillow)."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "media-sources/icon.png"
DESTINATION = ROOT / "App/Resources/Coreography.icns"
ICON_SIZE = (1024, 1024)


def main() -> None:
    with Image.open(MASTER) as image:
        if image.width != image.height:
            raise ValueError("The icon master must be square")

        DESTINATION.parent.mkdir(parents=True, exist_ok=True)
        image.convert("RGBA").resize(ICON_SIZE, Image.Resampling.LANCZOS).save(
            DESTINATION, format="ICNS"
        )


if __name__ == "__main__":
    main()
