# NianBox development

NianBox is a macOS-only fork of Peekaboo, with a standalone single-user server.
The user requested replacement of the upstream mobile/CloudKit contract on 2026-10-23.
Upstream instructions remain retrievable in Git history.

- Preserve the corner panel, menu bar, global shortcut and SwiftData offline capture.
- Use NianBox Server as cross-device authority; REST and MCP share SQLite transactions.
- Completed tasks persist until explicit deletion. Tombstones persist indefinitely.
- Never reset user stores or commit tokens. New stores use NianBox's own directory.
- The Xcode generator owns targets and signing. Keep only macOS targets and no paid Apple capabilities.
- Sync work must verify durable outbox recovery, idempotency, concurrency and deletion conflicts.
- Before committing, run server tests, project-generation verification and relevant macOS tests.
- Record verification and physical/deployment limitations in docs/verification.md.
- Keep changes local unless the user authorizes remote operations.

For protocol or persistence changes, read docs/sync.md.
For deployment and backup work, read docs/deployment.md.
