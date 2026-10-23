# Release workflow

`VERSION` defines the app/server release. Update it, the server package metadata and `__version__`, add `docs/releases/vVERSION.md`, regenerate the Xcode project, and pass `Scripts/check_version.py`, project verification, server tests and macOS tests before tagging.

Publishing a `vX.Y.Z` Git tag runs the complete native Linux AMD64/ARM64 and macOS checks. The macOS job builds one ad-hoc-signed Universal app (arm64 + x86_64, macOS 14+), creates and mounts a DMG headlessly, verifies its signature/entitlements/architectures and Finder layout, then uploads the DMG and SHA256SUMS to a draft release. No Finder scripting, host mouse injection, Apple credentials or paid signing service is needed.

After those gates pass, the publishing job builds the server image with the same version, revision metadata, provenance and SBOM. The final job smoke-tests the downloaded image, downloads the draft DMG and verifies its checksum, publishes the GitHub Release, and promotes the exact image index to `stable` and `vX.Y.Z`. The `X.Y.Z` tag, `vX.Y.Z` tag and `stable` must resolve to one digest. A version older than the latest published release cannot roll stable backwards. Routine `main` pushes publish only `:main` and commit tags.

A failed run can leave a draft release or an unpromoted versioned image; neither is a completed release. Retry failed jobs. Published assets are preserved on retries. If stable promotion fails after publishing the release, retry the final job and verify all three digests before claiming completion. Source tags and published DMGs must not be silently replaced.

Local reproduction (Python 3.10+):

```sh
python3 -m venv .local/packaging-venv
.local/packaging-venv/bin/python -m pip install -r Scripts/dmg-requirements.txt
NIANBOX_PACKAGING_PYTHON="$PWD/.local/packaging-venv/bin/python" bash Scripts/build_release.sh
```

Use a fresh output directory to rebuild an existing local release. Packaging refuses to overwrite a DMG. Tests that operate Finder or keyboards belong in the isolated VM; read `docs/macos-vm-testing.md` first.

The free personal build is not Apple-notarized. Release notes and the DMG explain the macOS Privacy & Security first-launch decision. Never disable Gatekeeper/SIP or silently approve a security dialog. Validate DMG layout and the installed app in the VM separately; Intel runtime on physical Intel hardware remains a separate acceptance gate even though both slices are built and inspected.
