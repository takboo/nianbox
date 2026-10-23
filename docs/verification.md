# Verification record

Source baseline: Peekaboo `54c23bf`. Workspace was empty with no local commits or data when implementation began on 2026-10-23.

Phase 1: 17 backend tests pass, including actual SDK Streamable HTTP transport, REST/MCP shared persistence, fail-closed auth, input validation, restart receipts, CAS concurrency, pagination, tombstones and SQLite online backup/restore. Deterministic Xcode generation passes and verifies exactly three macOS targets and network-client-only sandbox entitlements. macOS build and 46 unit tests pass (Xcode 26.2, unsigned test build).

No remote push, release, existing data migration, personal Hermes configuration change or live server deployment has occurred. Physical phone interaction, Mac power-off testing, external TLS/private-network reachability and human UX acceptance require the intended deployment/devices.

Phase 2: 58 macOS unit tests pass, including 12 SyncEngine fault/recovery cases. The production SwiftData model + durable outbox + SyncEngine + URLSession client passed a standalone integration run against the real Docker service. A task created using the installed Hermes MCP client was imported into a disk-backed SwiftData store with notes, priority and due date; an offline Mac capture survived store reopen, uploaded to the server, and a Mac completion round trip remained present after another reopen. The standalone harness uses the same production sources as the app; visible UI acceptance is separate.

Container verification: Compose built and ran on Docker 29.8.2, loopback port 18988, isolated project `nianbox-verification`. A saved task was read back byte-for-byte after container recreation using the same named volume.
