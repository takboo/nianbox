import os
import secrets
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID, uuid4, uuid5, NAMESPACE_URL

from fastapi import FastAPI, Query, Request
from fastapi.responses import JSONResponse
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.concurrency import run_in_threadpool
from pydantic import ValidationError

from .models import MAX_SQLITE_INTEGER, Mutation, Patch, Priority, Status
from .store import Store, StoreError


class Boundary:
    """Authenticate REST and MCP before dispatch, reject browser origins and bound bodies."""
    def __init__(self, app, token: str):
        self.app, self.token = app, token.encode()

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        headers = dict(scope['headers'])
        if scope['path'] == '/health' and scope['method'] == 'GET':
            return await self.app(scope, receive, send)
        authorization = headers.get(b'authorization', b'')
        if not secrets.compare_digest(authorization, b'Bearer ' + self.token):
            return await JSONResponse({'error': 'unauthorized'}, status_code=401,
                                      headers={'WWW-Authenticate': 'Bearer'})(scope, receive, send)
        if b'origin' in headers:
            return await JSONResponse({'error': 'browser_origin_forbidden'}, status_code=403)(scope, receive, send)
        chunks, size = [], 0
        while True:
            message = await receive()
            if message['type'] == 'http.disconnect':
                return
            size += len(message.get('body', b''))
            if size > 262144:
                return await JSONResponse({'error': 'body_too_large'}, status_code=413)(scope, receive, send)
            chunks.append(message.get('body', b''))
            if not message.get('more_body', False):
                break
        delivered = False
        async def replay():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {'type': 'http.request', 'body': b''.join(chunks), 'more_body': False}
            return await receive()
        await self.app(scope, replay, send)


def create_app(db_path: str | None = None, token: str | None = None):
    token = token if token is not None else os.environ.get('NIANBOX_API_TOKEN', '')
    if len(token) < 32 or not token.isascii() or any(c.isspace() for c in token):
        raise RuntimeError('NIANBOX_API_TOKEN must be at least 32 non-whitespace ASCII characters')
    store = Store(db_path or os.environ.get('NIANBOX_DB', '/data/nianbox.sqlite'))
    allowed_hosts = os.environ.get('NIANBOX_ALLOWED_HOSTS', 'localhost,127.0.0.1,[::1],testserver').split(',')
    mcp = FastMCP('nianbox', stateless_http=True, json_response=True, streamable_http_path='/',
                  transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=True,
                     allowed_hosts=[h + ':*' for h in allowed_hosts] + allowed_hosts))

    def apply(task_id, kind, patch, base_version, mutation_id):
        return store.mutate(Mutation(mutationId=mutation_id or uuid4(), taskId=task_id,
                                    baseVersion=base_version, kind=kind, patch=Patch.model_validate(patch)))

    def query_tasks(status, due_before, limit, offset):
        if not 1 <= limit <= 500 or not 0 <= offset <= MAX_SQLITE_INTEGER:
            raise ValueError('invalid_pagination')
        if due_before and due_before.tzinfo is None:
            raise StoreError('due_before_requires_timezone', status=422)
        due = due_before.astimezone(timezone.utc).isoformat() if due_before else None
        return {'tasks': store.list(status, due, limit, offset)}

    @mcp.tool()
    async def list_tasks(status: Status | None = None, due_before: datetime | None = None,
                         limit: int = 200, offset: int = 0) -> dict:
        """List retained tasks (including completed history), excluding deleted tasks. Paginate with offset."""
        return await run_in_threadpool(query_tasks, status, due_before, limit, offset)

    @mcp.tool()
    async def get_task(id: UUID) -> dict:
        """Read a task and its version. Deleted tasks are not returned."""
        return await run_in_threadpool(store.get, str(id))

    @mcp.tool()
    async def create_task(title: str, notes: str | None = None, status: Status = 'todo',
                    priority: Priority = 'none', dueAt: datetime | None = None,
                    id: UUID | None = None, mutationId: UUID | None = None) -> dict:
        """Capture a task; only title is required. Reuse id and mutationId for a retry."""
        task_id = id or uuid4()
        return await run_in_threadpool(apply, task_id, 'create', dict(title=title, notes=notes, status=status, priority=priority, dueAt=dueAt),
                     0, mutationId or uuid5(NAMESPACE_URL, f'nianbox:create:{task_id}'))

    @mcp.tool()
    async def update_task(id: UUID, version: int, patch: Patch, mutationId: UUID | None = None) -> dict:
        """Update only supplied fields using the version returned by get_task. Null clears notes/dueAt.
        On version_conflict, reread and decide whether to retry; completed history is retained.
        """
        return await run_in_threadpool(apply, id, 'update', patch.model_dump(exclude_unset=True), version, mutationId)

    @mcp.tool()
    async def complete_task(id: UUID, version: int, mutationId: UUID | None = None) -> dict:
        """Mark done without deleting history. Supply current version; reuse mutationId for retries."""
        return await run_in_threadpool(apply, id, 'update', {'status': 'done'}, version, mutationId)

    @mcp.tool()
    async def delete_task(id: UUID, version: int, mutationId: UUID | None = None) -> dict:
        """Explicitly delete a task using a permanent tombstone. Deletion wins over stale edits."""
        return await run_in_threadpool(apply, id, 'delete', {}, version, mutationId)

    @asynccontextmanager
    async def lifespan(app):
        async with mcp.session_manager.run():
            yield

    from . import __version__
    app = FastAPI(title='NianBox Server', version=__version__, lifespan=lifespan,
                  docs_url=None, redoc_url=None, openapi_url=None)
    app.state.store = store
    app.add_middleware(Boundary, token=token)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=allowed_hosts)

    @app.exception_handler(StoreError)
    async def store_error(request, error):
        return JSONResponse({'error': error.code, 'current': error.current}, status_code=error.status)

    @app.exception_handler(ValidationError)
    async def validation_error(request, error):
        return JSONResponse({'error': 'invalid_task'}, status_code=422)

    # Do not echo request bodies (which contain personal notes) in validation errors.
    from fastapi.exceptions import RequestValidationError
    @app.exception_handler(RequestValidationError)
    async def request_validation_error(request, error):
        return JSONResponse({'error': 'invalid_request'}, status_code=422)

    @app.get('/health')
    def health():
        return {'status': 'ok'}

    @app.get('/v1/tasks')
    def tasks(status: Status | None = None, due_before: datetime | None = None,
              limit: Annotated[int, Query(ge=1, le=500)] = 200,
              offset: Annotated[int, Query(ge=0, le=MAX_SQLITE_INTEGER)] = 0):
        return query_tasks(status, due_before, limit, offset)

    @app.get('/v1/tasks/{id}')
    def task(id: UUID):
        return store.get(str(id))

    @app.post('/v1/tasks', status_code=201)
    def create(patch: Patch, request: Request):
        task_id = uuid4()
        key = request.headers.get('Idempotency-Key')
        # Deterministic task identity makes POST retries safe with a supplied key.
        if key:
            try:
                mutation_id = UUID(key)
            except ValueError:
                return JSONResponse({'error': 'invalid_idempotency_key'}, status_code=422)
            task_id = uuid5(NAMESPACE_URL, 'nianbox:rest:' + str(mutation_id))
        else:
            mutation_id = uuid4()
        return apply(task_id, 'create', patch.model_dump(exclude_unset=True), 0, mutation_id)

    @app.patch('/v1/tasks/{id}')
    def update(id: UUID, patch: Patch, version: Annotated[int, Query(ge=1, le=MAX_SQLITE_INTEGER)], mutationId: UUID):
        return apply(id, 'update', patch.model_dump(exclude_unset=True), version, mutationId)

    @app.delete('/v1/tasks/{id}')
    def delete(id: UUID, version: Annotated[int, Query(ge=0, le=MAX_SQLITE_INTEGER)], mutationId: UUID):
        return apply(id, 'delete', {}, version, mutationId)

    @app.post('/v1/mutations')
    def mutate(mutation: Mutation):
        return store.mutate(mutation)

    @app.get('/v1/changes')
    def changes(after: Annotated[int, Query(ge=0, le=MAX_SQLITE_INTEGER)] = 0,
                limit: Annotated[int, Query(ge=1, le=500)] = 200,
                cursor_digest: Annotated[str | None, Query(pattern='^[0-9a-f]{64}$')] = None):
        return store.changes(after, limit, cursor_digest)

    @app.get('/v1/export')
    def export():
        return store.export()

    app.mount('/mcp', mcp.streamable_http_app())
    return app
