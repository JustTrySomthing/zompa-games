#!/usr/bin/env python3
"""Build the official Drop Four .zomp archive and its catalog entry."""
import hashlib
import json
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

from catalog_art import add_catalog_art

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
request = json.loads((root / ".github/release-request.json").read_text())
version = sys.argv[2] if len(sys.argv) > 2 else request["version"]
build = request["build"]
if len(version.split(".")) != 3 or not all(part.isascii() and part.isdigit() for part in version.split(".")):
    raise ValueError("Expected a numeric x.y.z version")
if type(build) is not int or build < 1:
    raise ValueError("Expected a positive build number")

renamed = tuple(map(int, version.split("."))) >= (1, 3, 2)

manifest = {
    "schema": 1,
    "id": "drop-four",
    "title": "Cats vs Dogs" if renamed else "Drop Four",
    "version": version,
    "build": build,
    "runtime": "love-11.5",
    "entry": "main.lua",
    "modes": ["solo", "local", "online"],
}
source = root / "drop-four" / version
source_manifest = source / "zompa.json"
if source_manifest.is_file():
    declared = json.loads(source_manifest.read_text())
    if declared["id"] != manifest["id"] or declared["version"] != version:
        raise ValueError("Reference manifest and build request do not match")
    if len(sys.argv) == 2 and declared["build"] != build:
        raise ValueError("Reference manifest build and release request do not match")
    manifest = declared
    build = manifest["build"]
filename = "Cats-vs-Dogs" if renamed else "Drop-Four"
package = out / f"{filename}-{version}.zomp"
with ZipFile(package, "w", ZIP_DEFLATED) as archive:
    manifest_text = json.dumps(manifest, indent=2) + "\n"
    archive.writestr(ZipInfo("zompa.json"), manifest_text, ZIP_DEFLATED)
    archive.writestr(ZipInfo("zompado.json"), manifest_text, ZIP_DEFLATED)
    names = ["conf.lua", "main.lua"]
    instructions = source / "how-to-play.txt"
    names.append("how-to-play.txt")
    help_bytes = instructions.read_bytes()
    if len(help_bytes) > 16 * 1024 or not help_bytes.decode("utf-8").strip():
        raise ValueError("how-to-play.txt must be nonblank UTF-8 and fit in 16 KiB")
    names.extend(name for name in ("zompa.lua", "zompado.lua") if (source / name).is_file())
    names.extend(name for name in ("rules.lua", "view.lua") if (source / name).is_file())
    for directory in ("art", "audio", "fonts"):
        names.extend(path.relative_to(source).as_posix()
                     for path in sorted((source / directory).rglob("*")) if path.is_file())
    for name in names:
        archive.writestr(ZipInfo(name), (source / name).read_bytes(), ZIP_DEFLATED)

catalog = {
    "schema": 2,
    "archive": [],
    "games": [{
        **{key: manifest[key] for key in ("id", "title", "version", "build", "modes")},
        "format": "zomp",
        "localSaves": manifest.get("localSaves", True),
        **{key: manifest[key] for key in ("minZompaBuild", "onlineProtocol") if key in manifest},
        "url": f"https://github.com/JustTrySomthing/zompado-games/releases/download/drop-four-v{version}/{package.name}",
        "size": package.stat().st_size,
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
    }],
}
add_catalog_art(root, catalog["games"][0])

(out / "catalog-v2.json").write_text(json.dumps(catalog, indent=2) + "\n")
