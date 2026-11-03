#!/usr/bin/env python3
"""Pin the Cask to a verified public release. Writes locally; never pushes or publishes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
VERSION = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
REPOSITORY = "https://github.com/takboo/nianbox"


def release_version(metadata):
    tag = metadata["tag_name"]
    if (not re.fullmatch("v" + VERSION, tag) or metadata.get("draft") is not False
            or metadata.get("prerelease") is not False or not metadata.get("published_at")
            or metadata.get("html_url") != f"{REPOSITORY}/releases/tag/{tag}"):
        raise ValueError("Expected a published stable NianBox release")
    version = tag[1:]
    for name in [f"NianBox-{version}-universal.dmg", "SHA256SUMS"]:
        assets = [a for a in metadata["assets"] if a["name"] == name]
        if (len(assets) != 1 or assets[0].get("state") != "uploaded" or assets[0].get("size", 0) <= 0
                or assets[0]["browser_download_url"] != f"{REPOSITORY}/releases/download/{tag}/{name}"):
            raise ValueError("Missing or invalid release asset: " + name)
    return version


def verified_checksum(version, checksums, dmg):
    expected_name = f"NianBox-{version}-universal.dmg"
    lines = checksums.strip().splitlines()
    if len(lines) != 1:
        raise ValueError("Expected exactly one DMG checksum")
    parts = lines[0].split()
    if len(parts) != 2 or not re.fullmatch(r"[0-9a-f]{64}", parts[0]) or parts[1] != expected_name:
        raise ValueError("Unexpected checksum filename or format")
    if hashlib.sha256(dmg).hexdigest() != parts[0]:
        raise ValueError("Downloaded DMG does not match SHA256SUMS")
    return parts[0]


def render_cask(version, checksum):
    if not re.fullmatch(VERSION, version) or not re.fullmatch(r"[0-9a-f]{64}", checksum):
        raise ValueError("Invalid Cask identity")
    return '''cask "nianbox" do
  version "%s"
  sha256 "%s"

  url "https://github.com/takboo/nianbox/releases/download/v#{version}/NianBox-#{version}-universal.dmg"
  name "NianBox"
  desc "Corner panel for offline notes and tasks with a self-hosted sync server"
  homepage "https://github.com/takboo/nianbox"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "NianBox.app"

  caveats <<~EOS
    This build is ad-hoc signed and is not notarized by Apple.
    Review macOS Privacy & Security if the first downloaded launch is blocked.
    Save unfinished drafts and quit NianBox before upgrading.
    Local tasks, pending changes, settings, and credentials are preserved on uninstall.
  EOS
end
''' % (version, checksum)


def reject_downgrade(existing, version):
    match = re.search(r'^  version "(' + VERSION + r')"$', existing, re.MULTILINE)
    if match and tuple(map(int, version.split("."))) < tuple(map(int, match[1].split("."))):
        raise ValueError("Refusing to move the Cask backwards to an older release")


def download(url, limit):
    request = urllib.request.Request(url, headers={"User-Agent": "NianBox-cask-maintenance"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Release response exceeds the expected size")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", default="latest", help="Published vX.Y.Z tag, or latest")
    parser.add_argument("--output", type=Path, default=ROOT / "Casks/nianbox.rb")
    parser.add_argument("--check", action="store_true", help="Verify the existing Cask without writing")
    args = parser.parse_args()
    if args.release != "latest" and not re.fullmatch("v" + VERSION, args.release):
        parser.error("Use latest or a stable vX.Y.Z release")
    endpoint = "latest" if args.release == "latest" else "tags/" + args.release
    metadata = json.loads(download("https://api.github.com/repos/takboo/nianbox/releases/" + endpoint, 1_048_576))
    version = release_version(metadata)
    if args.output.exists():
        reject_downgrade(args.output.read_text(), version)
    if args.release != "latest" and metadata["tag_name"] != args.release:
        raise ValueError("Release tag mismatch")
    base = f"{REPOSITORY}/releases/download/v{version}/"
    sums = download(base + "SHA256SUMS", 4096).decode("utf-8")
    dmg = download(base + f"NianBox-{version}-universal.dmg", 256 * 1024 * 1024)
    checksum = verified_checksum(version, sums, dmg)
    for asset in metadata["assets"]:
        if asset["name"] == f"NianBox-{version}-universal.dmg" and asset.get("digest"):
            if asset["digest"] != "sha256:" + checksum:
                raise ValueError("GitHub asset digest mismatch")
    rendered = render_cask(version, checksum)
    if args.check:
        if args.output.read_text() != rendered:
            raise ValueError("Cask differs from verified public release; run without --check to update")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    print(f"Verified NianBox {version}: {checksum}; " + ("Cask is current" if args.check else f"wrote {args.output}"))


if __name__ == "__main__":
    main()
