"""Publish versioned Zompa packages and maintain the current catalog."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
# Sandbox packages stay available in the repository for development.
SANDBOX_GAMES = set()


def run(*args, **kwargs):
    return subprocess.check_output(args, **kwargs)


def verify_candidate(path, repo, sdk):
    manifest = sdk.validate(path, require_three_modes=True)
    if manifest["id"] != path.parent.parent.name:
        raise ValueError(f"Game ID and directory do not match: {path}")
    if manifest.get("onlineProtocol") != "turns-v1":
        raise ValueError(f"Official games require the shared turns-v1 protocol: {path}")
    return sdk.catalog_entry(path, manifest, repo)


def prepare(workspace, repo, sdk):
    import zipfile

    feed = json.loads((ROOT / "catalog-v2.json").read_text())
    current = {game["id"]: game for game in feed["games"]}
    candidates = []
    for path in sorted(ROOT.glob("*/packages/*.zomp")):
        game = path.parent.parent.name
        if game in SANDBOX_GAMES:
            continue
        with zipfile.ZipFile(path) as archive:
            metadata = json.loads(sdk.checked_text(archive, "zompa.json", 4096))
        build = metadata.get("build") if isinstance(metadata, dict) else None
        if type(build) is not int:
            raise ValueError(f"Invalid build in {path}")
        old = current.get(game)
        if old and build < old["build"]:
            continue
        if old and build == old["build"]:
            with path.open("rb") as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != old["sha256"]:
                    raise ValueError("Published builds are immutable. Increase the version and build.")
            continue
        entry = verify_candidate(path, repo, sdk)
        if old and old["version"] == entry["version"]:
            raise ValueError("Use a new release version.")
        scenario = path.with_suffix(".scenario.json")
        if not scenario.is_file():
            raise ValueError(f"Missing Android test scenario: {scenario}")
        artifact = f"game-{game}-{build}"
        staging = workspace / artifact
        staging.mkdir(parents=True)
        shutil.copyfile(path, staging / path.name)
        shutil.copyfile(scenario, staging / "scenario.json")
        (staging / "catalog-v2.json").write_text(json.dumps(
            {"schema": 2, "games": [entry], "archive": []}
        ) + "\n")
        candidates.append({"artifact": artifact, "package": str(path.relative_to(ROOT)),
                           "sha256": entry["sha256"]})
    return candidates


def update(feed, entry):
    games = feed["games"]
    old = next((g for g in games if g["id"] == entry["id"]), None)
    if old and old["build"] >= entry["build"]:
        if old["build"] == entry["build"] and old["sha256"] != entry["sha256"]:
            raise ValueError("Published builds are immutable. Increase the version and build.")
        return False
    if not isinstance(entry["modes"], list) or "solo" not in entry["modes"] or not set(entry["modes"]) <= {"solo","local","online"}:
        raise ValueError("The installed Zompa catalog reader requires Solo support.")
    if old:
        if old["version"] == entry["version"]:
            raise ValueError("Use a new release version.")
        if old not in feed.setdefault("archive", []):
            feed["archive"].append(old)
        games[games.index(old)] = entry
    else:
        games.append(entry)
    return True


def publish(verified, sdk):
    repo = os.environ["GITHUB_REPOSITORY"]
    endpoint = f"repos/{repo}/contents/catalog-v2.json"
    candidates = []
    app_feed = json.loads(run("curl", "-fsSL",
        "https://raw.githubusercontent.com/JustTrySomthing/zompa/main/update.json"))
    for verified_game in verified:
        path = ROOT / verified_game["package"]
        entry = verify_candidate(path, repo, sdk)
        if entry["sha256"] != verified_game["sha256"]:
            raise ValueError(f"Package differs from the Android-tested bytes: {path}")
        if entry["minZompaBuild"] > app_feed["build"]:
            raise ValueError(f"Publish a compatible version of Zompa before listing {path}.")
        tag = f"{entry['id']}-v{entry['version']}"
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk", required=True, type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare", type=Path)
    mode.add_argument("--verified")
    args = parser.parse_args()
    sys.path.insert(0, str(args.sdk.resolve()))
    import zomp

    if args.prepare is not None:
        candidates = prepare(args.prepare, os.environ["GITHUB_REPOSITORY"], zomp)
        print(json.dumps(candidates, separators=(",", ":")))
    else:
        publish(json.loads(args.verified), zomp)


if __name__ == "__main__":
    main()
