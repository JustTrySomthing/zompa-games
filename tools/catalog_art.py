"""Validate optional artwork and add its references to a Zompa catalog entry."""

import json
import re


def add_catalog_art(root, entry):
    art = root / "catalog-art" / entry["id"] / entry["version"]
    preview_path = art / "preview.json"
    if preview_path.is_file():
        preview = json.loads(preview_path.read_text())
        cover = preview.get("cover")
        shots = preview.get("screenshots", [])
        if cover is not None and cover != "cover.webp":
            raise ValueError("Cover must be cover.webp")
        if not isinstance(shots, list) or len(shots) > 8:
            raise ValueError("Use up to eight screenshots")
        files = [cover] if cover else []
        for shot in shots:
            filename = shot["file"]
            label = shot["label"]
            if (not re.fullmatch(r"shot-[1-8]\.webp", filename)
                    or filename in files
                    or not isinstance(label, str)
                    or not 1 <= len(label.strip()) <= 100):
                raise ValueError("Each screenshot needs a distinct filename and short description")
            files.append(filename)
        for filename in files:
            image = art / filename
            if not image.is_file() or not 16 <= image.stat().st_size <= 350 * 1024:
                raise ValueError(f"Missing image or invalid image size: {filename}")
            with image.open("rb") as stream:
                header = stream.read(12)
            if header[:4] != b"RIFF" or header[8:] != b"WEBP":
                raise ValueError(f"Expected a WebP image: {filename}")
        if cover:
            entry["cover"] = cover
        if shots:
            entry["screenshots"] = [shot for shot in shots if shot["file"] in ("shot-1.webp", "shot-2.webp", "shot-3.webp")]
            if len(shots) > 3:
                entry["gallery"] = shots

