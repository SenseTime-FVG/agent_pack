#!/usr/bin/env python3
"""Fetch and install skills from a manifest URL or bundled manifest.

Usage:
    python fetch-skills.py --product hermes [--manifest-url URL] [--config-dir DIR]
    python fetch-skills.py --product openclaw [--manifest-url URL] [--config-dir DIR]
"""
import argparse
import json
import os
import sys
import urllib.request
import urllib.error
import zipfile
import tempfile
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BUNDLED_MANIFEST = os.path.join(SCRIPT_DIR, "..", "config", "skill-manifest.json")
DEFAULTS_FILE = os.path.join(SCRIPT_DIR, "..", "config", "defaults.json")

SKILL_DIRS = {
    "hermes": os.path.expanduser("~/.hermes/skills"),
    "openclaw": os.path.expanduser("~/.openclaw/workspace/skills"),
}


def load_defaults() -> dict:
    """Load defaults.json to get the manifest URL."""
    try:
        with open(DEFAULTS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def fetch_manifest(url: str) -> dict | None:
    """Fetch remote manifest. Returns None on failure."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "AgentPack/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.load(resp)
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError) as exc:
        print(f"WARNING: Could not fetch remote manifest: {exc}", file=sys.stderr)
        return None


def load_bundled_manifest() -> dict:
    """Load the bundled fallback manifest."""
    try:
        with open(BUNDLED_MANIFEST, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"version": 1, "skills": []}


def download_skill(source_url: str, dest_dir: str, name: str) -> bool:
    """Download a skill from source URL and extract to dest_dir/name/."""
    skill_dir = os.path.join(dest_dir, name)
    os.makedirs(skill_dir, exist_ok=True)

    try:
        req = urllib.request.Request(source_url, headers={"User-Agent": "AgentPack/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            content_type = resp.headers.get("Content-Type", "")
            data = resp.read()

            if source_url.endswith(".zip") or "zip" in content_type:
                with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
                    tmp.write(data)
                    tmp_path = tmp.name
                try:
                    with zipfile.ZipFile(tmp_path, "r") as zf:
                        zf.extractall(skill_dir)
                finally:
                    os.unlink(tmp_path)
            else:
                skill_file = os.path.join(skill_dir, "SKILL.md")
                with open(skill_file, "wb") as f:
                    f.write(data)

        print(f"  Installed: {name} -> {skill_dir}")
        return True
    except (urllib.error.URLError, urllib.error.HTTPError, zipfile.BadZipFile) as exc:
        print(f"  FAILED: {name} — {exc}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="Fetch and install skills from manifest")
    parser.add_argument("--product", required=True, choices=["hermes", "openclaw"])
    parser.add_argument("--manifest-url", default="")
    parser.add_argument("--skills-dir", default="", help="Override skill install directory")
    args = parser.parse_args()

    defaults = load_defaults()
    manifest_url = args.manifest_url or defaults.get("skill_manifest_url", "")

    manifest = None
    if manifest_url:
        print(f"Fetching skill manifest from {manifest_url}...")
        manifest = fetch_manifest(manifest_url)

    if manifest is None:
        print("Using bundled skill manifest as fallback.")
        manifest = load_bundled_manifest()

    skills = manifest.get("skills", [])
    if not skills:
        print("No skills to install.")
        return

    dest_dir = args.skills_dir or SKILL_DIRS.get(args.product, "")
    if not dest_dir:
        print(f"ERROR: Unknown product '{args.product}'", file=sys.stderr)
        sys.exit(1)

    os.makedirs(dest_dir, exist_ok=True)
    print(f"Installing skills to {dest_dir}...")

    installed = 0
    failed = 0
    for skill in skills:
        target = skill.get("target", "")
        if target not in (args.product, "both"):
            continue
        if download_skill(skill["source"], dest_dir, skill["name"]):
            installed += 1
        else:
            failed += 1

    print(f"\nDone: {installed} installed, {failed} failed.")
    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
