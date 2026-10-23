# macOS VM acceptance

Use an isolated macOS desktop for interactive automation. Host build/unit checks remain noninteractive. The current reusable environment belongs to the sibling `dsh-coopanion` project; read that project's `docs/macos-vm-testing.md` before starting it. Its VM data, base image, SSH identity and retention rules remain owned by that project.

## Verified environment on 2026-10-23

- Existing `dsh-macos15-test`, Tart 2.40.1, macOS 15.7.7 (24G720), arm64 `VirtualMac2,1`, one 1440×1080 display; console user admin/501, guest timezone UTC.
- Guest Command Line Tools provide Swift 6.1.2; full Xcode and the XCUITest runtime are absent. No Xcode download, base-image replacement or VM clone was needed.
- The VM ran without a host graphics window, shared directory, clipboard, audio or USB forwarding. Dedicated SSH authentication retained strict host-key checking.
- The guest already reported Accessibility and event-posting access. No TCC database, system protection or host permission was changed. Taking evidence screenshots triggered a guest `com.apple.sshd-session` screen-recording approval dialog; it was not automatically approved. It remained in the guest desktop, outside the NianBox panel.
- NianBox used `~/nianbox-testing/` for inputs, fixed source and independent run artifacts. The dsh-coopanion checkout was clean before/after and was not updated. The prepared base VM was not started or modified.

## Test method and identity

The production app was built and signed on the host, then exported with its fixed Git source bundle. Both source and app archive hashes were verified in the guest before execution. The test controller and probe were transferred separately and their hashes were also matched after retrieving results.

| Input | Identity |
| --- | --- |
| Product source (clean in guest) | `5654d5617a934599c318c58060462d50e04cbaf7` |
| Release executable SHA-256 | `486d0922449273fd2095329329fa38bd8ed34dd37a5539c3c480c0350996d20c` |
| Source bundle SHA-256 | `62e7e5704aafd85fef64619cd98d32bf4c9bb5deccda9fb0fe0f60174ecb4c75` |
| App archive SHA-256 | `2c1406d5b855553dd8503881838fcb63ee5cc14aca41d0760bad871084fb5205` |
| `Scripts/vm_ui_probe.swift` SHA-256 | `8a5d2212b1d219efd47123ada701604e88757b512df48c176e0263a01fa3c8fa` |
| `Scripts/vm_ui_smoke.py` SHA-256 | `000e369cd52f89b3d65e4d382b04ad35ba7dda4a46a6a19c73140b0667275818` |

`vm_ui_probe.swift` uses native Accessibility discovery and CoreGraphics mouse/keyboard events. It rejects a physical Mac before any Accessibility/desktop call; that rejection was separately verified on the host. The Python controller also requires VirtualMac, launches only the supplied NianBox app and refuses to proceed if another NianBox process is already running.

Button presses and typing use actual guest OS events. Dragging starts a native drag, then rereads the destination's current Accessibility frame before releasing; the upstream panel reveals drag targets during a drag, so an initial coordinate is not a stable destination. Keyboard modifiers are explicitly released between events. Initial driver calibration failures remain in the raw evidence; they were not product changes.

This is native functional acceptance, not execution of the existing XCTest suite. Full XCUITest still requires a guest with a suitable Xcode runtime. The product binary and panel layout were unchanged during this follow-up.

## Results

All **six native checks passed** in the final run:

| Check | Verified behavior |
| --- | --- |
| Capture, status, menu, history | Title-only capture with Return; double-click to In Progress; completion retained in Done; task menu and rename |
| Native drag ordering | Two equal-priority tasks reordered by guest OS drag; before/after row positions and screenshots recorded |
| Long title | Exact title remains accessible and wraps onto multiple lines |
| Search | Case-insensitive match, no-match state and restoration after closing search |
| Global shortcut, corner, disk reopen | Shortcut while Finder is foreground; offline record survives process exit/reopen; corner reveal and hide |
| Hermes → server → guest app | Installed Hermes native MCP client creates the task; VM panel imports it; guest click completes it; authenticated REST confirms status and completion time |

The first four UI checks use fresh in-memory app launches. The shortcut/corner check runs the normal app with disk-backed SwiftData in its own guest container and a run-specific synthetic title. The Hermes case uses a fresh in-memory cache with a random test credential placed only in NianBox's own guest sandbox directory. Guest sandbox enforcement and network-client entitlement remain enabled in the signed Release app.

The backend for this run was an isolated Docker Compose project bound only to host loopback. A dedicated SSH reverse forward exposed it only at guest loopback, still requiring Bearer authentication. It did not open an unauthenticated LAN/public endpoint or use the user's real Hermes profile.

Host evidence is retained under `.local/vm/evidence/vm-native-round3/` with the original JSON report, UI trees and screenshots; preliminary runs are retained separately. Guest originals remain under `~/nianbox-testing/run-5654d56/`. These private local artifacts are ignored by Git. The controller records source, app, probe and controller identities in every result.

After retrieval, the generated guest/host Hermes fixture files were removed, the tunnel and test container were stopped, and the VM was returned to its original stopped state. Data volumes, VM disks, source and evidence were retained.

## Repeat procedure

1. Check the sibling project's instructions, current VM state, active tests and capacity. Start only the test VM with its existing controller; leave the prepared base alone.
2. Export a clean product commit with `git bundle`, build its Release app and archive it with `ditto`. Transfer them into a new guest `nianbox-testing` directory through the dedicated SSH channel. Verify source, archive, binary signature and executable hashes in the guest.
3. Transfer the two VM test scripts from the intended source separately if they are newer than the product build. Record their hashes. In the guest, compile and run (choose a fresh output directory):

   ```sh
   swiftc -parse-as-library vm_ui_probe.swift -o probe
   python3 vm_ui_smoke.py --app NianBox.app --probe probe \
     --source ../source-COMMIT --output native-RUN
   ```

4. For the sixth check, first use `Scripts/hermes_smoke.py` against an isolated authenticated test server. Transfer its chmod-600 fixture into the guest NianBox sandbox, make the server reachable through a loopback-only SSH reverse tunnel, and add `--fixture /absolute/guest/path/to/fixture.json`. The fixture's URL must refer to that guest-accessible endpoint. Test credentials must remain outside Git and logs.
5. Retrieve the result directory byte-for-byte. Verify all result identities, assertions and screenshots. Remove only generated credential fixtures, close the tunnel/container, and stop the VM if it was started by this run and no other work has taken ownership.

If guest permissions are missing, authorize the intended capability in the guest explicitly. Do not grant host desktop access, edit TCC databases or disable system protection to bypass it. A guest screen-recording dialog can appear during evidence capture and remains a guest-only permission decision.

## Remaining boundaries

These results cover one virtual display and synthetic OS input. Physical keyboard/mouse behavior, multiple physical displays/Spaces, mixed DPI, launch-at-login, human UX acceptance, actual phone conversations and deployment to an always-on HTTPS/private-network server remain separate acceptance gates. A host-powered VM also cannot prove service availability with the physical host powered off.
