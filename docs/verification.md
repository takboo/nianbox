# Verification and remaining acceptance

Date: 2026-10-23. Baseline: Peekaboo `54c23bf`. The workspace was empty (no local commits, files or data) when implementation began. Work began locally on `codex/nianbox-macos`. Remote publication was subsequently authorized by the user; see the image distribution follow-up below.

## Phase 1 — macOS-only fork and standalone server

- Local commit: `73d8e09`.
- Removed the mobile source/tests/targets/scheme, CloudKit/APNs capabilities and bootstrap/observers, upstream signing/team/container identifiers, and daily completed-task cleanup. LICENSE is unchanged.
- FastAPI + SQLite REST/MCP share one transactional store; Compose uses a persistent volume and loopback binding.
- Initial checks: 17 server tests and 46 retained macOS unit tests passed.
- Docker 29.8.2 built and ran the service. A diagnostic task was read back unchanged after recreating the container with its named volume.

## Phase 2 — offline macOS synchronization

- Local commit: `392e52d`.
- SwiftData task changes and outbox entries commit together. Prepared requests, IDs and patches survive reopen; server pages and cursors also commit together. Deletion wins, with rejected local patches retained for export. Notes/due dates use the same server model.
- Phase 2 checks: 58 macOS unit tests passed (12 sync cases). Final stabilization expands this to **60 passing unit tests**.
- `Scripts/verify_sync.sh` compiles production models, TaskStore, SyncEngine and URLSession sources into a noninteractive integration executable. Against the actual Docker server, it verified disk-backed import of a Hermes-created task (notes, high priority, due date), offline capture surviving reopen and upload, Mac completion reaching the server, and completed history surviving another local reopen.
- A dedicated NianBox store path is used. No upstream/user store was opened or migrated.

## Phase 3 — Hermes and stabilization

- Installed Hermes source checked: `v0.22.2+canary.20261019T071120Z-385-g0b10b9f815`. Its native client imports Streamable HTTP and resolves `${ENV_VAR}` in headers; no compatibility adapter is needed.
- `Scripts/hermes_smoke.py`, run with the installed Hermes Python environment and an isolated HERMES_HOME, connected its real `MCPServerTask` to Docker. All six tools were discovered and exercised, including idempotent create retry, read, update, completion and tombstone deletion. REST read the same stored task. No LLM/phone messages or private live Hermes configuration were used or changed.
- Final backend suite: **19 passing tests**. Covers auth on REST/MCP, host/origin/body boundaries, validation, CRUD/filtering, idempotency after restart, concurrent CAS, incremental pagination, offline create/delete, permanent tombstones, retained completed history, and backup/restore.
- Actual container online-backup and JSON-export commands ran successfully. The backup was restored into a **fresh second Docker volume**; server identity and all 7 task/tombstone records at that snapshot matched the export.
- Deterministic generator verification passes: exactly NianBox, NianBoxTests and NianBoxUITests; all macOS; no paid capabilities. CI runs server checks and macOS unit tests only. Interactive UI tests are manual.
- Release builds with free ad-hoc signing; the Release configuration disables injected debug entitlements. Signature/entitlements and linked frameworks are inspected separately from tests; no Apple team, CloudKit, APNs or remote publication is involved.

## Interactive UI evidence and limitations

The signed UI runner successfully displayed the task created by the installed Hermes client, clicked its completion button, and verified `done` through REST. A subsequent full UI run reported **4 passes and 1 drag-order failure**: capture/status/menu editing, long title wrapping, search, and Hermes→panel→server completion passed.

Later single-case attempts also failed before tasks were saved. The user reported simultaneous mouse use and permission dialogs. These tests emit real desktop input; focus and event interference make those failures inconclusive. Interactive runs were stopped at the user's steering. The original panel layout is retained; a speculative drag-layout change was reverted. Stable task-store ordering has automated unit coverage, but physical drag acceptance remains pending. Unit-test hosts now skip global shortcuts, corner monitoring, welcome windows and server sync. Background Keychain reads disallow authentication UI; connection issues are shown in settings instead of triggering prompts.

No claim is made that the full UI suite or human UX acceptance has passed. Prior failure artifacts remain under `.local/UITestDerivedData/Logs/Test`; they are not distribution artifacts.

## Isolated VM follow-up — 2026-10-23

The sibling dsh-coopanion macOS test VM was reused without opening a host VM window or sharing host input. A clean `5654d56` source bundle and the exact signed Release executable were transferred and verified. The guest has Command Line Tools but no full Xcode, so acceptance used native Accessibility discovery plus guest CoreGraphics input, with a guard that rejects physical Macs. The host rejection check passed.

All **6 native VM checks passed**: capture/status/menu/completed history, real OS drag ordering, long-title wrapping, search, global shortcut/corner reveal/disk reopen, and installed Hermes MCP client→server→VM panel→completion back to REST. Source, binary and driver hashes plus original screenshots/results are recorded in [VM acceptance](macos-vm-testing.md). The product app/layout was unchanged. The previous host XCTest failures remain historical results; the full XCTest UI suite was not rerun or relabeled as passing.

Guest Accessibility/event access was already available. Screenshot capture produced a guest screen-recording approval dialog; it was not automatically approved, and no host permissions were changed. After recording results, the fixture, tunnel and test container were cleaned up and the VM returned to stopped. This follow-up also reran the 19 server tests and deterministic generation check successfully.

## GitHub and image distribution follow-up — 2026-10-23

The user explicitly authorized a public `takboo/nianbox` repository and public GHCR server images. Distribution configuration now separates pull-only deployment (`compose.yaml`) from optional local builds (`compose.build.yaml`). CI checks native Linux AMD64/ARM64 and macOS before publishing a multi-platform image on `main`; other branches and pull requests cannot publish. Docker/Actions updates are tracked by Dependabot.

Local verification before the first push:

- **19 server tests, 60 macOS unit tests**, deterministic macOS project verification, `git diff --check` and Actionlint 1.7.12 passed. No desktop automation was run.
- Official Python 3.12.15 slim/trixie is pinned to its multi-platform digest. Production input allowlisting, wheel-only/no-bytecode installation and an explicit UID/GID replace the earlier loose context and default group.
- ARM64 image `sha256:5a933bcf4cb3e96a281e651ff68fc5f5e1c340f3c97f78718fe378d52266b99f` is **174,368,714 bytes** locally, versus approximately 184 MB previously. This is uncompressed Docker image size, not network download size. Shell and pip remain from the standard slim runtime; no claim of an absolute minimum or distroless image is made. The original MIT license/copyright is included at `/app/LICENSE`, with a CI comparison against the repository license.
- `Scripts/verify_container.py` passed against the actual image with read-only root, UID/GID 10001, dropped capabilities, no-new-privileges, a private throwaway volume, **128 MiB memory and 0.5 CPU**. Verified authenticated REST/MCP sharing data, all six MCP tools, restart persistence, idempotency replay, stable server identity, backup and export. No pytest/compiler/Git/Node is installed. Process RSS in this sample was **68,228 kB (about 67 MiB)**; capacity under sustained load is not established.
- Random test tokens existed only in a mode-0600 temporary file and runtime environment. The check removed only its own disposable container and volume. User data and previous verification volumes were preserved.

The public source was pushed as `01f1ec8` to [takboo/nianbox](https://github.com/takboo/nianbox). SSH port 22 was unavailable; GitHub's SSH-over-443 route succeeded with existing strict host-key verification. The first ARM64 CI run failed during pytest collection. The same `ModuleNotFoundError: nianbox` was reproduced locally with the `pytest` entry point (the previously used `python -m pytest` passed). An explicit project-root pytest path fixes collection; the exact CLI invocation now passes all 19 tests. Docker dependency updates are constrained to Python 3.12 patch/digest changes; interpreter upgrades need deliberate review.

The first successful remote workflow and anonymous GHCR pull still need verification; publication configuration alone is not evidence of a downloadable image. The intended always-on deployment and real phone workflow remain separate acceptance gates.

## Remaining live acceptance

1. Deploy Compose on the intended always-on host and verify the real HTTPS/Tailscale URL and ACLs from the Hermes host and Mac.
2. Use the actual phone Hermes channel for natural-language creation, querying, modification and completion. Verify while the Mac is powered off, then start NianBox and observe the task/history.
3. VM native drag/drop, shortcut, corner reveal and disk reopen have passed. Complete physical input/multi-display/Spaces, live network recovery, launch-at-login and human UX acceptance separately. Full XCUITest execution requires a guest Xcode runtime.
4. macOS notarization/distribution, old Peekaboo data migration and production cutover are outside the completed local verification. No Mac installation or GitHub release has been performed. Server image publication is tracked separately above.

## Reproduce without operating the desktop

```sh
cd Server && uv sync --locked && uv run pytest -q
# From repository root:
bundle exec ruby Scripts/verify_project_generation.rb
xcodebuild test -project NianBox.xcodeproj -scheme NianBox \
  -destination 'platform=macOS' -only-testing:NianBoxTests CODE_SIGNING_ALLOWED=NO
# After producing a fresh isolated fixture with the Hermes smoke script:
Scripts/verify_sync.sh .local/e2e.json
```

See [Hermes](hermes.md), [deployment/restore](deployment.md) and [sync contract](sync.md) for setup and recovery rules. Test fixtures contain only random test credentials and generated diagnostic tasks, are ignored by Git, and should be handled as private files.
