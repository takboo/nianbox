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

Local checks during distribution preparation:

- **19 server tests, 60 macOS unit tests**, deterministic macOS project verification, `git diff --check` and Actionlint 1.7.12 passed. No desktop automation was run.
- Official Python 3.12.15 slim/trixie is pinned to its multi-platform digest. Production input allowlisting, wheel-only/no-bytecode installation and an explicit UID/GID replace the earlier loose context and default group.
- ARM64 image `sha256:5a933bcf4cb3e96a281e651ff68fc5f5e1c340f3c97f78718fe378d52266b99f` is **174,368,714 bytes** locally, versus approximately 184 MB previously. This is uncompressed Docker image size, not network download size. Shell and pip remain from the standard slim runtime; no claim of an absolute minimum or distroless image is made. The original MIT license/copyright is included at `/app/LICENSE`, with a CI comparison against the repository license.
- `Scripts/verify_container.py` passed against the actual image with read-only root, UID/GID 10001, dropped capabilities, no-new-privileges, a private throwaway volume, **128 MiB memory and 0.5 CPU**. Verified authenticated REST/MCP sharing data, all six MCP tools, restart persistence, idempotency replay, stable server identity, backup and export. No pytest/compiler/Git/Node is installed. Process RSS in this sample was **68,228 kB (about 67 MiB)**; capacity under sustained load is not established.
- Random test tokens existed only in a mode-0600 temporary file and runtime environment. The check removed only its own disposable container and volume. User data and previous verification volumes were preserved.

The public source was pushed as `01f1ec8` to [takboo/nianbox](https://github.com/takboo/nianbox). SSH port 22 was unavailable; GitHub's SSH-over-443 route succeeded with existing strict host-key verification. The first ARM64 CI run failed during pytest collection. The same `ModuleNotFoundError: nianbox` was reproduced locally with the `pytest` entry point (the previously used `python -m pytest` passed). An explicit project-root pytest path fixes collection; the exact CLI invocation now passes all 19 tests. Docker dependency updates are constrained to Python 3.12 patch/digest changes; interpreter upgrades need deliberate review.

The `482106e` workflow passed and published a public multi-platform package. All native Linux AMD64/ARM64 and macOS checks also passed for `6ec3d32`, but its publishing job stalled in QEMU preparation and reported `Failed to restore: Egress is over the account limit.` This was the GitHub Actions image cache, not application data or GHCR. The stalled run was cancelled. Publication now disables QEMU/build caches, installs only the ARM64 emulator and has bounded timeouts. CI also cancels superseded runs and avoids duplicate Dependabot push/PR runs.

Final publication **passed** for `b60a7dd36fc05bcd85f2ef63b0c29a83f2cf8a84`: [GitHub CI run](https://github.com/takboo/nianbox/actions/runs/39918693563). Both native Linux server jobs, macOS checks and publishing succeeded. The [GHCR package](https://github.com/takboo/nianbox/pkgs/container/nianbox) is public. A pull with a fresh Docker configuration containing no registry credentials succeeded; the downloaded image's revision label matched the commit. The actual downloaded ARM64 image then passed the restricted-container checks again (MCP/REST, restart, idempotency, backup/export, permissions and license).

Verified multi-platform deployment reference:

```dotenv
NIANBOX_IMAGE=ghcr.io/takboo/nianbox@sha256:325d335d39d5969af3d773d2309a51cb0e57f8919ee716911a0973c04d75ea50
```

The index contains Linux AMD64 and ARM64 plus SLSA provenance and SPDX SBOM attestations. Compressed image-layer bytes total **52,820,235 (AMD64)** and **53,049,978 (ARM64)**, about 53 MB per architecture before protocol overhead. Layers already cached on a host reduce the actual download. The downloaded ARM64 image is **174,332,089 bytes** uncompressed; measured process RSS after its checks was **68,676 kB (about 67 MiB)**. The separate local AMD64 image passed the same check under Docker emulation (150,334,810 bytes); its emulated RSS is not a native Linux memory benchmark.

Raw local evidence: `.local/ghcr-anonymous-pull.log`, `.local/ghcr-container-check.json`, `.local/ghcr-distribution.json`, `.local/github-final-jobs.json`. No user token, database or private configuration was published. The intended always-on deployment and real phone workflow remain separate acceptance gates.

## Remaining live acceptance

1. Deploy Compose on the intended always-on host and verify the real HTTPS/Tailscale URL and ACLs from the Hermes host and Mac.
2. Use the actual phone Hermes channel for natural-language creation, querying, modification and completion. Verify while the Mac is powered off, then start NianBox and observe the task/history.
3. VM native drag/drop, shortcut, corner reveal and disk reopen have passed. Complete physical input/multi-display/Spaces, live network recovery, launch-at-login and human UX acceptance separately. Full XCUITest execution requires a guest Xcode runtime.
4. macOS notarization, old Peekaboo data migration and production cutover remain outside the completed verification. The v0.2.0 candidate was installed only in the isolated VM; host installation and human first-launch acceptance remain pending. GitHub release and image distribution are tracked separately below.

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

## v0.2.0 release — published and verified

The user explicitly requested publication of a new version, a matching `stable` image, automatic DMG releases, a corrected project link, configurable capture keys and new artwork. The chosen design is original D with its 3D drawer/note identity retained; a flat simplification was rejected. The final imagegen master is stored in `Branding/` and technical app/menu exports are committed.

Local checks: **19 server tests and 65 macOS unit tests passed**, deterministic generation and Actionlint passed. The Universal Release app builds with arm64/x86_64 slices and only the existing three sandbox entitlements. The Universal DMG passes headless layout, Applications-link, architecture and signature checks. A first VM Finder check exposed incomplete view settings (blank background and default icon size); packaging now uses pinned dmgbuild with a 1x/2x TIFF, and a second VM screenshot confirms the designed background, 96-point icons and drag guidance. The final icon preserves D's 3D drawer and adds a rounded terracotta plate with transparent outer padding for macOS 14/15. Runtime container checks passed for the 0.2.0 server. A targeted VM check passed custom shortcut recording, global activation, conflict detection, disk reopen, disabling and restoring default. Modifier release detects combinations consumed by another global binding without adding an event tap or requesting Accessibility. Recording also cancels on window focus loss. The final six native VM checks passed using clean source `148e6093a5667f68f10929146dcea5565eca336b` and the Universal app installed from the candidate DMG into the guest Applications directory. This run covers capture/status/history, native drag, wrapping, search, corner/default shortcut/disk reopen, and configurable shortcut/conflict/cancel/focus-loss/reopen/disable/default restoration. The recorded Settings Accessibility tree also exposes the GitHub link URL as `https://github.com/takboo/nianbox`. No host input or host app data was used. The candidate executable SHA-256 is `b09012b24a018e73c87ff836b7513b38852e91150bca5c65b3a6f2a235e7b066`; candidate DMG SHA-256 is `4b6e1559444cdaa0510951aecb576e89201901381f380e4df3ba3cd6a91c9c7d`. Screenshots, original UI trees and results are retained under `.local/v020-vm-final-evidence/`. Hermes synchronization was not rerun in this UI-only release follow-up; prior protocol evidence remains above.

The implementation and `v0.2.0` tag were pushed at `148e609`. The [tag workflow](https://github.com/takboo/nianbox/actions/runs/39927590258) passed all five jobs: native Linux AMD64 and ARM64 checks, macOS checks/Universal DMG, multi-platform image publishing, and release/stable verification. The separate main workflow also passed. The [public release](https://github.com/takboo/nianbox/releases/tag/v0.2.0) contains the automatically generated Universal DMG and SHA256SUMS. Future version tags use the same checked workflow.

| Published artifact | Identity |
| --- | --- |
| Source tag | `v0.2.0` → `148e6093a5667f68f10929146dcea5565eca336b` |
| GitHub DMG (3,129,906 bytes) | SHA-256 `6e4f4cc0119852fec134c26a1d59e0c66fab97dcb6a0ead7ec1aa41c7c1c5889` |
| GitHub app executable | SHA-256 `39861268f8032a2f4a92e296a0cfb835c292223281c634670a9f61be10b2d8d4` |
| Server multi-platform index | `ghcr.io/takboo/nianbox@sha256:9d303e46def7bcde70fea236274aa91bb0c8bc49f6008b58fae429d8b9bfe9a6` |

An unauthenticated public download matched both SHA256SUMS and GitHub's asset digest. The actual GitHub-built app separately passed signature, three sandbox entitlements, both architecture slices and all six native VM checks; it is distinct from the host-built candidate above. Original results/UI trees/screenshots are under `.local/v020-vm-github-evidence/`. The Settings tree reports the corrected repository URL. This release follow-up does not replace the earlier Hermes integration evidence or establish phone/physical Intel/multi-display acceptance.

A new Docker configuration containing no registry credentials successfully pulled `:stable`. Independent anonymous index queries confirmed `:stable`, `:0.2.0` and `:v0.2.0` resolve to the exact index above, containing Linux AMD64/ARM64 plus attestation manifests. The downloaded ARM64 image's revision/version labels match `148e609`/`v0.2.0`. Restricted runtime checks passed again: Bearer auth, six MCP tools sharing REST data, container-restart persistence, idempotency, server identity, backup/export, UID/GID 10001 and read-only root. This sample used 128 MiB and 0.5 CPU; image size is 174,332,145 bytes uncompressed, measured process RSS 68,696 kB. These are sample measurements, not a load benchmark.

Evidence also includes `.local/v020-github-ci.json`, `.local/v020-github-release.json`, `.local/v020-github-dmg-check.json`, `.local/v020-ghcr-final-indexes.json`, `.local/v020-ghcr-anonymous-pull.log` and `.local/v020-ghcr-container-check.json`. Only the new disposable runtime container/volume and temporary VM Applications copy were removed; user stores, synthetic guest history and raw evidence were retained. The test VM is stopped again, the prepared base remained stopped, and no sibling repository source was written. The host app was not replaced. Public builds are ad-hoc signed and not Apple-notarized; a browser-downloaded first launch and its Gatekeeper decision remain human acceptance.

## Menu bar icon and motion prototype — 2026-10-23

A review-only prototype, `nianbox-menubar-prototype.html`, is retained in this chat's visualization storage outside Git, following the branding rule for preview variants. It derives a monochrome drawer, round knob and folded note from the approved App icon. Local-save acknowledgement and server acknowledgement are separate; empty background polls remain static. The preview includes ten individual states and eight simulated scenarios, including offline recovery, overlapping capture/sync, cancellation, local-save failure, invalid credentials and remote deletion conflicts.

Headless Chrome with a temporary browser profile verified all ten state controls, a complete online capture/save/sync sequence, transient success returning to the idle image, pixel-identical icons throughout an empty poll, static sync feedback with reduced motion, and concurrent input with a prior record's sync/acknowledgement. Light/dark screenshots and a 320 CSS-pixel layout check passed, with no horizontal overflow or JavaScript errors. A final visual pass confirmed the raised paper stays within the icon bounds. An initial widget-state echo interrupted playback; the prototype now ignores its own echoed snapshot, and the affected flows were rechecked successfully. Review screenshots and `menubar-browser-verification.json` remain beside the prototype.

This is simulated visual/interaction evidence only. Production SwiftUI/AppKit, task storage, sync code and shipped icon assets were not changed, and no user data, network service or native desktop was operated. Native macOS rendering, animation delivery/energy use, VoiceOver and VM acceptance remain implementation-stage checks; server, project-generation and macOS test suites were not rerun for this isolated preview. No commit, remote publication or host app installation was performed. The temporary loopback preview server was stopped after inspection.

### Prototype v2: small-size errors and capture easing

User review found the three warning badges too similar at menu-bar size and the input transition too abrupt. The revised preview replaces them with three different large features: disconnected plugs above the drawer for connection failure, a large negative-space cross in the drawer front for local-save failure, and divergent folded notes for deletion conflict. It includes a permanent light/dark comparison at exactly 18 CSS pixels; individual state controls also use 18-pixel glyphs. Exact failure causes remain available in text rather than relying on icon interpretation alone.

Input lift now lasts 540 ms with a quintic easing curve that starts and ends with zero velocity and acceleration, a slight rotation delay, and continuity from the previously rendered paper pose. A dedicated input-only replay scenario was added. Headless browser inspection verified distinct rendered error images, all six comparison canvases at 18 pixels, no initial-position jump when starting input, intermediate animation frames, a stable final pose, reduced-motion stillness, light/dark presentation and a 320-pixel layout without horizontal overflow or JavaScript errors. This establishes rendering behavior, not human recognition accuracy. Evidence is retained beside the preview as `menubar-v2-*.png` and `menubar-v2-browser-verification.json`; the original v1 fragment was retained separately. This remains an isolated visual prototype with no native app or data-path changes.

## Native menu lifecycle and consistency fixes — 2026-10-23

Implemented the approved v2 menu-bar companion as native 18-point template images with 1x/2x representations, driven by the long-lived capture state and typed sync activity. Local commit and fully acknowledged server sync have independent feedback. Empty pulls keep identical pixels, transfer motion is delayed by 600 ms, successful sync never masks waiting/blocked/failed work, and system Reduce Motion uses static states without a repeating timer. Tasks/Backlog drafts retain separate titles/priorities across scope changes and temporary composer removal; only successful commit or explicit Cancel clears the current draft. These unsubmitted drafts remain session-local.

Regression evidence was established before the fixes: the native lost-response/remote-edit test retained stale title/notes while reporting Synced; the scope-switch test closed the capture session. Server tests reproduced exact-second/fractional due-filter omissions, SQLite integer overflow and a write-lock-induced shared-event-loop stall of 0.885 s. Restoring a backup and writing past an old cursor also bypassed the old high-water check. The fixes retain a canonical server snapshot under pending overlays, compare full-precision UTC instants, offload complete MCP database operations to worker threads, bound SQLite integers, and atomically persist/send cursor history digests. Canonical snapshots and digest fields are optional additions to existing stores; no reset or token changes are performed.

Current local checks passed: 26 server tests; 77 macOS unit tests, including disk-reopened lost receipts, later local patches, deletion conflicts, capture retention and lifecycle feedback; deterministic macOS-only project generation; Universal Release build and signature checks; distinct native template glyphs at 18/36 pixels; and diff whitespace checks. Tooling was prepared in ignored task-local directories (Ruby 3.4.11/Bundler 4.0.11 and the locked Python environment). Host macOS is 15.7.9, Xcode 26.3; Xcode license/initialization was explicitly authorized and completed by the user.

An isolated real HTTP fault harness committed a Mac request, withheld its response, performed a real MCP update on that task and replayed the unchanged request. Production SwiftData/ServerClient/SyncEngine sources converged to the newer canonical title/notes before reporting Synced. The installed Hermes native MCP client also passed six-tool CRUD/history/idempotency checks with an isolated HERMES_HOME and synthetic credentials. Raw local evidence includes `.local/repro-native.xcresult`, `.local/repro-server.log`, `.local/repro-restore.log`, `.local/final-native.xcresult`, `.local/server-full.log`, `.local/native-menu-icons.png` and `.local/hermes-live.log`.

A fresh task-owned Tart 2.41.1 VM is running for interactive acceptance, using image `ghcr.io/cirruslabs/macos-sequoia-base@sha256:eee659985b01e4df2a6c0754bd8d25e54969933c43fdcd4edef8bea337b3d354`, macOS 15.7.7/VirtualMac2,1, 2 CPUs, 4096 MiB and one 1440x1080 display. It uses a dedicated SSH key/known-hosts file and default NAT because host-only networking requires macOS 26. Host windows, clipboard, audio and USB sharing are disabled. Native VM acceptance results will be recorded separately after execution. No host app installation, store reset or remote Git publication has been performed. `dueAt` still does not schedule notifications.
