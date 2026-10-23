# Data and sync contract

Public task fields: `id` (UUID), `title`, nullable `notes`, `status`, `priority`, nullable `dueAt`, `createdAt`, `updatedAt`, nullable `completedAt`, nullable internal `deletedAt`. `version` is an internal server change sequence. Mac manual ordering remains a local UI preference.

All REST/MCP writes use one SQLite transaction (`BEGIN IMMEDIATE`), storing the task, append-only change record and idempotency receipt atomically. Times are server-assigned UTC; device clocks never resolve conflicts. SQLite uses WAL, FULL synchronous writes and a 15 second busy timeout.

`POST /v1/mutations` accepts `{mutationId, taskId, kind, baseVersion, patch}`. Kinds are `create`, `update`, `delete`. Create needs title and baseVersion 0. Update changes only supplied fields; null clears notes/dueAt. Other required fields cannot be null. A repeated mutation ID with identical content returns its original response; different content returns 409. Receipts and tombstones are retained indefinitely in v1.

Updates compare baseVersion to the current version. On 409 `version_conflict`, the response includes `current`. The sender must rebase deliberately. Delete wins over concurrent edits regardless of baseVersion. Updates/creates cannot resurrect a tombstone, even from a long-offline device. Retrying a delete is safe. An offline create followed by delete may create a tombstone directly.

`GET /v1/changes?after=0&limit=200` returns `{changes, cursor, hasMore, serverId}`. Persist each page's records and cursor in one local transaction. Replay is harmless. Change sequence is monotonic, unrelated to timestamps. The stream includes tombstones and completed tasks. Never advance a cursor from a write response: other task changes may precede that response. A cursor beyond the server high-water mark is rejected; serverId detects connecting to another database. Full SQLite restores preserve identity and receipts.

REST convenience endpoints: POST `/v1/tasks` (optional UUID `Idempotency-Key`, strongly recommended); GET `/v1/tasks/{id}`; PATCH `/v1/tasks/{id}?version=...&mutationId=...`; DELETE with those same query parameters. List supports status, due_before, limit and offset. The MCP update tool takes a `patch` object and current `version`; read before editing. Create accepts optional stable id/mutationId for safe retries.

Mac synchronization implementation and recovery behavior will be recorded with Phase 2 verification.
