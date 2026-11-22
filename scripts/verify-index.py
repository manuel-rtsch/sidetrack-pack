#!/usr/bin/env python3
"""Sanity-check the built index before it is published.

An APK whose metadata/<pkg>.yml is missing gets silently dropped from the index
with only a warning, so a pack can quietly publish with fewer apps than intended
— or none. This turns that into a hard failure, and prints what did make it in.

It also checks the three things that are expensive to notice after publishing:

  * the address in the signed index matches config.yml (a mismatch means
    clients fetch from a host that serves a different repo);
  * every referenced APK is actually on disk, with the sha256 the index claims;
  * each version carries exactly one APK file, so the universal and arm64 APKs
    of a Sidetrack release can never both end up under one versionCode.
"""
import hashlib
import json
import sys
from pathlib import Path

import yaml

INDEX = Path("repo/index-v2.json")
APPS = Path("apps.json")
CONFIG = Path("config.yml")


def fail(msg: str) -> int:
    print(f"::error::{msg}")
    return 1


def main() -> int:
    if not INDEX.exists():
        return fail(f"{INDEX} not found — did `fdroid update` run?")

    index = json.loads(INDEX.read_text())
    repo = index["repo"]
    packages = index["packages"]
    expected = {app["package"] for app in json.loads(APPS.read_text())}
    actual = set(packages)

    config_url = yaml.safe_load(CONFIG.read_text())["repo_url"]
    print(f"address:  {repo['address']}")
    print(f"config:   {config_url}")
    print(f"name:     {repo['name'].get('en-US', '?')}")
    print(f"packages: {len(packages)}")

    if repo["address"] != config_url:
        return fail(
            f"index address {repo['address']!r} does not match config.yml "
            f"{config_url!r} — the published index would point somewhere else"
        )

    problems = []
    for pkg in sorted(packages):
        meta = packages[pkg].get("metadata", {})
        summary = meta.get("summary", {}).get("en-US", "!! NO SUMMARY")
        print(f"\n  {pkg}")
        print(f"    {summary}")
        print(f"    license: {meta.get('license', '!! NONE')}")
        if not meta.get("license"):
            problems.append(f"{pkg}: no license in metadata")

        files = set()
        for fingerprint, ver in packages[pkg]["versions"].items():
            f = ver["file"]
            vc = ver["manifest"]["versionCode"]
            print(f"    vc={vc}  {f['name']}  {f['size']:,}B")
            files.add(f["name"])
            apk = Path("repo" + f["name"])
            if not apk.exists():
                problems.append(f"{pkg}: {apk} referenced by the index is missing")
            else:
                digest = hashlib.sha256(apk.read_bytes()).hexdigest()
                if digest != f["sha256"]:
                    problems.append(
                        f"{pkg}: {apk} sha256 {digest} != index {f['sha256']}"
                    )
        if len(files) != len(packages[pkg]["versions"]):
            problems.append(
                f"{pkg}: {len(packages[pkg]['versions'])} versions but only "
                f"{len(files)} distinct files — two APKs share a version"
            )
        if not meta.get("preferredSigner"):
            problems.append(f"{pkg}: no preferredSigner — the index did not record a signer")

    missing = sorted(expected - actual)
    if missing:
        return fail(f"Index is missing configured packages: {', '.join(missing)}")

    if problems:
        for p in problems:
            print(f"::error::{p}")
        return 1

    print("\nok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
