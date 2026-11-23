"""Publish versioned Zompa packages and maintain the current catalog."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from zipfile import ZipFile

from catalog_details import listing_details, validate_modes

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.check_output(args, **kwargs)


def package_entry(path, repo):
    size = path.stat().st_size
    if not 0 < size <= 64 * 1024 * 1024:
        raise ValueError(f"Invalid package size: {path}")
    with ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) > 4096 or len(set(n.lower() for n in names)) != len(names):
            raise ValueError(f"Invalid archive entries: {path}")
        if sum(i.file_size for i in archive.infolist()) > 192 * 1024 * 1024:
            raise ValueError(f"Expanded package exceeds player limit: {path}")
        if archive.testzip() or archive.getinfo("main.lua").file_size == 0:
            raise ValueError(f"Invalid package: {path}")
        manifest = json.loads(archive.read("zompa.json"))
    entry = {k: manifest[k] for k in ("id", "title", "version", "build", "modes")}
    game, version = entry["id"], entry["version"]
    if (not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", game) or len(game) > 64
            or game != path.parent.parent.name or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)
            or not re.fullmatch(r"[a-zA-Z0-9._-]+\.zomp", path.name)
            or not isinstance(entry["title"], str) or not 1 <= len(entry["title"].strip()) <= 90
            or type(entry["build"]) is not int or not 1 <= entry["build"] <= 2147483647
            or manifest.get("runtime") != "love-11.5" or manifest.get("entry") != "main.lua"
            or manifest.get("schema") != 1):
        raise ValueError(f"Invalid player manifest: {path}")
    tag = f"{game}-v{version}"
    entry.update(format="zomp", size=size, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                 url=f"https://github.com/{repo}/releases/download/{tag}/{path.name}")
    return entry, tag


def update(feed, entry):
    games = feed["games"]
    old = next((g for g in games if g["id"] == entry["id"]), None)
    if old and old["build"] >= entry["build"]:
        if old["build"] == entry["build"] and old["sha256"] != entry["sha256"]:
            raise ValueError("Published builds are immutable. Increase the version and build.")
        return False
    validate_modes(entry["modes"])
    entry.update(listing_details(ROOT, entry["id"], entry["version"]))
    if old:
        if old["version"] == entry["version"]:
            raise ValueError("Use a new release version.")
        if old not in feed.setdefault("archive", []):
            feed["archive"].append(old)
        games[games.index(old)] = entry
    else:
        games.append(entry)
    return True


def publish():
    repo = os.environ["GITHUB_REPOSITORY"]
    endpoint = f"repos/{repo}/contents/catalog-v2.json"
    candidates = []
    for path in sorted(ROOT.glob("*/packages/*.zomp")):
        entry, tag = package_entry(path, repo)
        candidates.append((entry, tag, path))
    for attempt in range(3):
        record = json.loads(run("gh", "api", endpoint + "?ref=main"))
        feed = json.loads(base64.b64decode(record["content"]))
        changed = False
        for entry, tag, path in sorted(candidates, key=lambda item: (item[0]["id"],item[0]["build"])):
            if not update(feed, entry):
                continue
            check = subprocess.run(["gh","release","view",tag], stdout=subprocess.DEVNULL)
            if check.returncode:
                run("gh","release","create",tag,str(path),"--target",os.environ["GITHUB_SHA"],
                    "--title",entry["title"]+" "+entry["version"],"--notes","Game package for Zompa.","--latest=false")
            with tempfile.TemporaryDirectory() as tmp:
                public = Path(tmp) / "public.zomp"
                run("curl","-fsSL","--retry","5","--retry-all-errors",entry["url"],"-o",str(public))
                if public.read_bytes() != path.read_bytes():
                    raise ValueError(f"Published download differs: {entry['url']}")
            changed = True
        if not changed:
            return
        data = (json.dumps(feed, indent=2, ensure_ascii=False)+"\n").encode()
        payload = dict(message="Update games available in Get Games", branch="main",
                       sha=record["sha"], content=base64.b64encode(data).decode())
        try:
            run("gh","api","--method","PUT",endpoint,"--input","-",input=json.dumps(payload).encode())
            return
        except subprocess.CalledProcessError:
            if attempt == 2:
                raise


if __name__ == "__main__":
    publish()
