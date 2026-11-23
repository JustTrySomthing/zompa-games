"""Validate the artwork and description for a new Get Games listing."""

import json
import re
import struct

REQUIRED_MODES = {"solo", "local", "online"}


def validate_modes(modes):
    if (not isinstance(modes, list)
            or not all(isinstance(mode, str) for mode in modes)
            or len(modes) != len(REQUIRED_MODES)
            or set(modes) != REQUIRED_MODES):
        raise ValueError("Provide Single Player, Pass & Play, and Online.")


def validate_instructions(archive):
    requirement = "Include a non-empty UTF-8 how-to-play.txt (up to 16 KiB) at the package root."
    try:
        instructions = archive.getinfo("how-to-play.txt")
    except KeyError:
        raise ValueError(requirement) from None
    if not 1 <= instructions.file_size <= 16 * 1024:
        raise ValueError(requirement)
    try:
        text = archive.read(instructions).decode("utf-8-sig")
    except UnicodeDecodeError:
        raise ValueError(requirement) from None
    if not text.strip() or any(not (char.isprintable() or char in "\n\r\t") for char in text):
        raise ValueError(requirement)


def webp_dimensions(image):
    with image.open("rb") as stream:
        header = stream.read(30)
    if header[:4] == b"RIFF" and header[8:12] == b"WEBP" and len(header) == 30:
        chunk = header[12:16]
        if chunk == b"VP8X" and not header[20] & 2:
            return tuple(1 + int.from_bytes(header[start:start + 3], "little")
                         for start in (24, 27))
        if chunk == b"VP8 " and header[23:26] == b"\x9d\x01\x2a":
            return tuple(value & 0x3FFF for value in struct.unpack_from("<HH", header, 26))
        if chunk == b"VP8L" and header[20] == 0x2F:
            bits = int.from_bytes(header[21:25], "little")
            return (1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF))
    raise ValueError(f"Expected a still WebP image: {image.name}")


def listing_details(root, game, version):
    art = root / "catalog-art" / game / version
    preview = json.loads((art / "preview.json").read_text(encoding="utf-8"))
    description = preview.get("description")
    if (not isinstance(description, str)
            or not 1 <= len(description.strip()) <= 600
            or "\n" in description.strip() or "\r" in description.strip()):
        raise ValueError("Provide a one-paragraph description of up to 600 characters.")

    cover = preview.get("cover")
    if cover != "cover.webp":
        raise ValueError("Provide cover.webp.")
    shots = preview.get("screenshots")
    if not isinstance(shots, list) or not 3 <= len(shots) <= 8:
        raise ValueError("Provide three to eight gameplay screenshots.")

    files = {cover}
    for shot in shots:
        if not isinstance(shot, dict):
            raise ValueError("Each screenshot needs a filename and short description.")
        filename, label = shot.get("file"), shot.get("label")
        if (not isinstance(filename, str)
                or not re.fullmatch(r"shot-[1-8]\.webp", filename)
                or filename in files
                or not isinstance(label, str)
                or not 1 <= len(label.strip()) <= 100):
            raise ValueError("Each screenshot needs a distinct filename and short description.")
        files.add(filename)

    for filename in sorted(files):
        image = art / filename
        if not image.is_file() or not 16 <= image.stat().st_size <= 350 * 1024:
            raise ValueError(f"Missing image or invalid image size: {filename}")
        dimensions = webp_dimensions(image)
        if filename == cover:
            legacy_cover = (game, version, dimensions) == ("drop-four", "1.3.12", (1080, 608))
            if dimensions != (1280, 720) and not legacy_cover:
                raise ValueError("The cover must be 1280 × 720.")
        elif min(dimensions) < 480 or max(dimensions) > 1600:
            raise ValueError(f"Screenshot dimensions are out of range: {filename}")

    return {"description": description.strip(), "cover": cover, "screenshots": shots}
