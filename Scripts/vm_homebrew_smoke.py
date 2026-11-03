#!/usr/bin/env python3
"""Install/upgrade/adopt/uninstall public DMGs in a dedicated VirtualMac; preserve existing guest data."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--older-cask", type=Path, required=True, help="Verified older public-release Cask generated into a new file")
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
model = subprocess.check_output(["sysctl", "-n", "hw.model"], text=True).strip()
if not model.startswith("VirtualMac"):
    parser.error("Refusing package installation on a physical Mac")
app = Path("/Applications/NianBox.app")
if app.exists() or subprocess.run(["pgrep", "-x", "NianBox"], capture_output=True).returncode == 0:
    parser.error("Existing app/process preserved; use a dedicated guest without an installed NianBox app")
args.source = args.source.resolve()
args.output.mkdir(parents=True, exist_ok=False)
env = os.environ.copy()
env.update(HOMEBREW_NO_AUTO_UPDATE="1", HOMEBREW_NO_ANALYTICS="1")
brew = "/opt/homebrew/bin/brew"
token = "takboo/nianbox/nianbox"
tap = Path("/opt/homebrew/Library/Taps/takboo/homebrew-nianbox")
if tap.exists():
    parser.error("Existing tap preserved; this check must own its tap")
data_root = Path.home() / "Library/Containers/org.nianbox.NianBox/Data/Library/Application Support/NianBox"
if not (data_root / "nianbox.store").exists():
    parser.error("Seed the dedicated guest's synthetic offline database before checking retention")
preferences = Path.home() / "Library/Containers/org.nianbox.NianBox/Data/Library/Preferences/org.nianbox.NianBox.plist"


def fingerprint():
    files = [p for p in data_root.rglob("*") if p.is_file()]
    if preferences.exists():
        files.append(preferences)
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}


before = fingerprint()
report = dict(virtualMachine=True, model=model, sourceCommit=subprocess.check_output(
    ["git", "-C", str(args.source), "rev-parse", "HEAD"], text=True).strip(),
    gatekeeperFirstLaunchTested=False, appLaunched=False, dataBefore=before, checks=[])


def run(name, command):
    started = time.monotonic()
    with (args.output / (name + ".log")).open("w") as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=600)
    item = dict(name=name, passed=result.returncode == 0, exitCode=result.returncode,
                seconds=round(time.monotonic() - started, 2))
    report["checks"].append(item)
    (args.output / "results.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(item), flush=True)
    if result.returncode:
        raise RuntimeError(name + " failed; see its log")


def assert_app_version(expected):
    with (app / "Contents/Info.plist").open("rb") as file:
        actual = plistlib.load(file)["CFBundleShortVersionString"]
    assert actual == expected, (actual, expected)
    assert fingerprint() == before, "Package operation changed offline data/preferences"


created_tap = False
try:
    run("tap-local-snapshot", [brew, "tap", "takboo/nianbox", str(args.source)])
    created_tap = True
    cask = tap / "Casks/nianbox.rb"
    original = cask.read_text()
    run("cask-style", [brew, "style", "--cask", str(cask)])
    import re
    old = args.older_cask.read_text()
    old_version = re.search(r'^  version "([^"]+)"$', old, re.MULTILINE)[1]
    new_version = re.search(r'^  version "([^"]+)"$', original, re.MULTILINE)[1]
    assert tuple(map(int, old_version.split("."))) < tuple(map(int, new_version.split(".")))
    cask.write_text(old)
    run("install-older-public-release", [brew, "install", "--cask", token])
    assert_app_version(old_version)
    cask.write_text(original)
    run("upgrade-public-release", [brew, "upgrade", "--cask", token])
    assert_app_version(new_version)
    run("verify-installed-signature", ["codesign", "--verify", "--deep", "--strict", str(app)])
    run("verify-installed-architectures", ["lipo", str(app / "Contents/MacOS/NianBox"), "-verify_arch", "arm64", "x86_64"])
    report["installedExecutableSHA256"] = hashlib.sha256((app / "Contents/MacOS/NianBox").read_bytes()).hexdigest()
    backup = args.output / "adoption/NianBox.app"
    backup.parent.mkdir()
    run("retain-identical-app-for-adoption", ["ditto", str(app), str(backup)])
    run("uninstall-preserving-data", [brew, "uninstall", "--cask", token])
    assert not app.exists() and fingerprint() == before
    run("stage-identical-manual-app", ["ditto", str(backup), str(app)])
    run("adopt-identical-app", [brew, "install", "--cask", "--adopt", token])
    assert_app_version(new_version)
    run("uninstall-adopted-app", [brew, "uninstall", "--cask", token])
    assert not app.exists() and fingerprint() == before
    report["dataPreserved"] = True
    report["oldVersion"], report["newVersion"] = old_version, new_version
finally:
    if created_tap:
        # Remove only this check's package registration; keep all application data.
        installed = subprocess.run([brew, "list", "--cask", token], env=env, capture_output=True)
        if installed.returncode == 0:
            run("cleanup-owned-package", [brew, "uninstall", "--cask", token])
        if (tap / "Casks/nianbox.rb").exists():
            (tap / "Casks/nianbox.rb").write_text((args.source / "Casks/nianbox.rb").read_text())
        run("remove-owned-tap", [brew, "untap", "takboo/nianbox"])
    report["dataAfter"] = fingerprint()
    (args.output / "results.json").write_text(json.dumps(report, indent=2))
assert report.get("dataPreserved") and all(c["passed"] for c in report["checks"])
