import hashlib
import json
import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from .models import Mutation, timestamp, utc_instant


class StoreError(Exception):
    def __init__(self, code: str, current=None, status=409):
        self.code, self.current, self.status = code, current, status
        super().__init__(code)


class Store:
    def __init__(self, path: str):
        self.path = path
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript("""
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY, body TEXT NOT NULL, version INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS changes (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS mutations (
                    id TEXT PRIMARY KEY, digest TEXT NOT NULL, response TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                INSERT OR IGNORE INTO metadata VALUES ('schemaVersion', '1');
                INSERT OR IGNORE INTO metadata VALUES ('serverId', lower(hex(randomblob(16))));
            """)
            if db.execute("SELECT value FROM metadata WHERE key='schemaVersion'").fetchone()[0] != '1':
                raise RuntimeError("Unsupported database schema; preserve the database and upgrade NianBox")

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.execute("PRAGMA synchronous=FULL")
        try:
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    def get(self, task_id: str, include_deleted=False):
        with self.connect() as db:
            row = db.execute("SELECT body FROM tasks WHERE id=?", (task_id,)).fetchone()
        if row is None:
            raise StoreError("not_found", status=404)
        task = json.loads(row[0])
        if task["deletedAt"] and not include_deleted:
            raise StoreError("not_found", status=404)
        return task

    def list(self, status=None, due_before=None, limit=200, offset=0):
        # Fields queried with json_extract stay parameterized, including filters.
        with self.connect() as db:
            # Existing records may use Z, offsets, or omitted fractional seconds.
            # SQLite date functions round fractions; compare exact UTC microseconds instead.
            db.create_function('utc_instant', 1, lambda value: utc_instant(value) if value else None,
                               deterministic=True)
            rows = db.execute("""SELECT body FROM tasks WHERE json_extract(body, '$.deletedAt') IS NULL
                AND (? IS NULL OR json_extract(body, '$.status')=?)
                AND (? IS NULL OR utc_instant(json_extract(body, '$.dueAt'))<=?)
                ORDER BY json_extract(body, '$.createdAt'), id LIMIT ? OFFSET ?""",
                (status, status, due_before, utc_instant(due_before) if due_before else None, limit, offset)).fetchall()
        return [json.loads(row[0]) for row in rows]

    def mutate(self, mutation: Mutation):
        data = mutation.model_dump(mode="json", exclude_unset=True)
        digest = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()
        task_id, mutation_id = str(mutation.taskId), str(mutation.mutationId)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            receipt = db.execute("SELECT digest,response FROM mutations WHERE id=?", (mutation_id,)).fetchone()
            if receipt:
                if receipt[0] != digest:
                    raise StoreError("idempotency_key_reused")
                return json.loads(receipt[1])
            row = db.execute("SELECT body,version FROM tasks WHERE id=?", (task_id,)).fetchone()
            current = json.loads(row[0]) if row else None
            if current and current['deletedAt']:
                if mutation.kind != 'delete':
                    raise StoreError("deleted", current)
                # Delete wins even if the sender's base predates deletion.
                result = {"task": current}
                db.execute("INSERT INTO mutations VALUES (?,?,?)", (mutation_id, digest, json.dumps(result)))
                return result
            if mutation.kind == 'create':
                if current:
                    raise StoreError("version_conflict", current)
                now = timestamp()
                current = dict(id=task_id, title='', notes=None, status='todo', priority='none',
                               dueAt=None, createdAt=now, updatedAt=now, completedAt=None, deletedAt=None)
            elif current is None:
                # An offline deletion of a never-uploaded create must still leave a tombstone.
                if mutation.kind != 'delete' or mutation.baseVersion != 0:
                    raise StoreError("not_found", status=404)
                now = timestamp()
                current = dict(id=task_id, title='', notes=None, status='todo', priority='none',
                               dueAt=None, createdAt=now, updatedAt=now, completedAt=None, deletedAt=None)
            elif row[1] != mutation.baseVersion and mutation.kind != 'delete':
                raise StoreError("version_conflict", current)
            patch = mutation.patch.model_dump(mode='json', exclude_unset=True)
            now = timestamp()
            previous_status = current['status']
            current.update(patch)
            if current['status'] == 'done':
                if previous_status != 'done' or current['completedAt'] is None:
                    current['completedAt'] = now
            else:
                current['completedAt'] = None
            current['updatedAt'] = now
            if mutation.kind == 'delete':
                current['deletedAt'] = now
            # Change sequence is the server-assigned version, independent of device clocks.
            cursor = db.execute("INSERT INTO changes(body) VALUES ('')").lastrowid
            current['version'] = cursor
            body = json.dumps(current, ensure_ascii=False)
            db.execute("UPDATE changes SET body=? WHERE seq=?", (body, cursor))
            db.execute("INSERT INTO tasks VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body,version=excluded.version",
                       (task_id, body, cursor))
            result = {"task": current}
            db.execute("INSERT INTO mutations VALUES (?,?,?)", (mutation_id, digest, json.dumps(result)))
        return result

    def changes(self, after: int, limit: int, cursor_digest: str | None = None):
        with self.connect() as db:
            db.execute('BEGIN')
            server_id = db.execute("SELECT value FROM metadata WHERE key='serverId'").fetchone()[0]
            high = db.execute('SELECT COALESCE(MAX(seq),0) FROM changes').fetchone()[0]
            if after > high:
                raise StoreError('cursor_ahead', status=409)
            anchor = db.execute('SELECT body FROM changes WHERE seq=?', (after,)).fetchone() if after else None
            digest = hashlib.sha256(anchor[0].encode()).hexdigest() if anchor else None
            if cursor_digest is not None and cursor_digest != digest:
                raise StoreError('history_diverged', status=409)
            rows = db.execute('SELECT seq,body FROM changes WHERE seq>? ORDER BY seq LIMIT ?', (after, limit + 1)).fetchall()
            more = len(rows) > limit
            rows = rows[:limit]
            return dict(changes=[json.loads(r[1]) for r in rows], cursor=rows[-1][0] if rows else after,
                        hasMore=more, serverId=server_id,
                        cursorDigest=hashlib.sha256(rows[-1][1].encode()).hexdigest() if rows else digest)

    def export(self):
        with self.connect() as db:
            db.execute('BEGIN')
            return dict(schemaVersion=1, exportedAt=timestamp(),
                        serverId=db.execute("SELECT value FROM metadata WHERE key='serverId'").fetchone()[0],
                        tasks=[json.loads(r[0]) for r in db.execute('SELECT body FROM tasks ORDER BY id')])

    def backup(self, destination: str):
        # SQLite online backup includes committed WAL data and produces a standalone database.
        target = Path(destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
        with self.connect() as db, sqlite3.connect(destination) as backup:
            db.backup(backup)
