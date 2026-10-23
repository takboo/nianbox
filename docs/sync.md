# Data and sync contract

Public task fields: `id` (UUID), `title`, nullable `notes`, `status`, `priority`, nullable `dueAt`, `createdAt`, `updatedAt`, nullable `completedAt`, nullable internal `deletedAt`. `version` is an internal server change sequence. Mac manual ordering remains a local UI preference.

All REST/MCP writes use one SQLite transaction (`BEGIN IMMEDIATE`), storing the task, append-only change record and idempotency receipt atomically. Times are server-assigned UTC; device clocks never resolve conflicts. SQLite uses WAL, FULL synchronous writes and a 15 second busy timeout.

`POST /v1/mutations` accepts `{mutationId, taskId, kind, baseVersion, patch}`. Kinds are `create`, `update`, `delete`. Create needs title and baseVersion 0. Update changes only supplied fields; null clears notes/dueAt. Other required fields cannot be null. A repeated mutation ID with identical content returns its original response; different content returns 409. Receipts and tombstones are retained indefinitely in v1.

Updates compare baseVersion to the current version. On 409 `version_conflict`, the response includes `current`. The sender must rebase deliberately. Delete wins over concurrent edits regardless of baseVersion. Updates/creates cannot resurrect a tombstone, even from a long-offline device. Retrying a delete is safe. An offline create followed by delete may create a tombstone directly.

`GET /v1/changes?after=0&limit=200` returns `{changes, cursor, hasMore, serverId}`. Persist each page's records and cursor in one local transaction. Replay is harmless. Change sequence is monotonic, unrelated to timestamps. The stream includes tombstones and completed tasks. Never advance a cursor from a write response: other task changes may precede that response. A cursor beyond the server high-water mark is rejected; serverId detects connecting to another database. Full SQLite restores preserve identity and receipts.

REST convenience endpoints: POST `/v1/tasks` (optional UUID `Idempotency-Key`, strongly recommended); GET `/v1/tasks/{id}`; PATCH `/v1/tasks/{id}?version=...&mutationId=...`; DELETE with those same query parameters. List supports status, due_before, limit and offset. The MCP update tool takes a `patch` object and current `version`; read before editing. Create accepts optional stable id/mutationId for safe retries.

## Mac offline recovery

SwiftData stores the task and `PendingMutation` in one explicit transaction. Autosave is disabled on the contexts used by TaskStore. Once a request is prepared, its body and UUID stay immutable across retries and restarts. Edits during an in-flight upload create later queue entries. A reply removes only its acknowledged entry, applies the canonical server record, then overlays later pending field patches. Manual row ordering stays local and does not generate server writes.

The engine pulls before uploads, verifies server identity, drains at most 100 operations, then pulls again. It stores each import page with its cursor atomically; write receipts never advance the pull cursor. A CAS rejection rebases only the changed local fields onto the server's current version using a fresh mutation ID; therefore unrelated remote fields survive. If the same field changed concurrently, the later accepted local patch wins. Pending edits overtaken by a remote tombstone are retained as blocked queue entries and included in local export, while the task stays deleted. Recover text from the export into a new task UUID deliberately; the old UUID cannot be restored.

Synchronization runs after local saves (300 ms debounce), connectivity recovery, wake and foreground activation, with a 60 second interval for remote changes. The corner panel keeps its original local refresh behavior. Network failure, 401/422 and unknown server errors leave the queue intact. The settings window shows status and pending/conflict counts and can export local tasks plus all queue entries without credentials.

Server URL and database identity are pinned to the local cache. A changed identity, mismatched URL or cursor ahead of the restored database pauses sync; export and reconcile before migration. There is deliberately no destructive reset button. Existing local-only records with version 0 are queued when first connecting, so upgrading from Phase 1 does not strand captures. Old upstream stores are never opened automatically.

