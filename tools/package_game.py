#!/usr/bin/env python3
"""Build the official Drop Four .zomp archive and its catalog entry."""
import hashlib
import json
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

root = Path(__file__).resolve().parent.parent
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
request = json.loads((root / ".github/release-request.json").read_text())
version = request["version"]
build = request["build"]
if len(version.split(".")) != 3 or not all(part.isascii() and part.isdigit() for part in version.split(".")):
    raise ValueError("Expected a numeric x.y.z version")
if type(build) is not int or build < 1:
    raise ValueError("Expected a positive build number")

manifest = {
    "schema": 1,
    "id": "drop-four",
    "title": "Drop Four",
    "version": version,
    "build": build,
    "runtime": "love-11.5",
    "entry": "main.lua",
    "modes": ["solo", "local", "online"],
}
package = out / f"Drop-Four-{version}.zomp"
with ZipFile(package, "w", ZIP_DEFLATED) as archive:
    archive.writestr(ZipInfo("zompado.json"), json.dumps(manifest, indent=2) + "\n", ZIP_DEFLATED)
    source = root / "drop-four" / version
    names = ["conf.lua", "main.lua"]
    if (source / "zompado.lua").is_file():
        names.append("zompado.lua")
    for name in names:
        archive.writestr(ZipInfo(name), (source / name).read_bytes(), ZIP_DEFLATED)

catalog = {
    "schema": 2,
    "archive": [],
    "games": [{
        **{key: manifest[key] for key in ("id", "title", "version", "build", "modes")},
        "format": "zomp",
        "url": f"https://github.com/JustTrySomthing/zompado-games/releases/download/drop-four-v{version}/{package.name}",
        "size": package.stat().st_size,
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
    }],
}
(out / "catalog-v2.json").write_text(json.dumps(catalog, indent=2) + "\n")
