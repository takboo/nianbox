import asyncio
import json
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
import pytest
from fastapi.testclient import TestClient
from nianbox.app import create_app
from nianbox.models import Mutation
from nianbox.store import Store, StoreError

TOKEN = 'test-only-' + 'a' * 40

@pytest.fixture
def client(tmp_path):
    app = create_app(str(tmp_path / 'test.sqlite'), TOKEN)
    with TestClient(app, headers={'Authorization': 'Bearer ' + TOKEN}) as client:
        yield client


def mutation(task_id=None, kind='create', version=0, patch=None, key=None):
    return dict(mutationId=str(key or uuid4()), taskId=str(task_id or uuid4()),
                kind=kind, baseVersion=version, patch=patch if patch is not None else {'title': 'Remember'})


def test_auth_and_boundary(client):
    for path in ['/v1/tasks', '/v1/changes', '/v1/export', '/mcp/']:
        assert client.get(path, headers={'Authorization': ''}).status_code == 401
        assert client.post(path, json={}, headers={'Authorization': 'Bearer wrong'}).status_code == 401
    assert client.get('/health', headers={'Authorization': ''}).status_code == 200
    assert client.get('/v1/tasks', headers={'Origin': 'https://evil.example'}).status_code == 403
    assert client.get('/v1/tasks', headers={'Host': 'evil.example'}).status_code == 400
    assert client.post('/v1/mutations', content=b'a' * 262145).status_code == 413


def test_token_fail_closed(tmp_path):
    for token in ['', 'short', 'x' * 32 + '\n', '汉' * 40]:
        with pytest.raises(RuntimeError):
            create_app(str(tmp_path / 'x.sqlite'), token)


def test_lifecycle_history_and_tombstone(client):
    create = mutation(patch={'title': '  A   thought\n', 'notes': 'details', 'dueAt': '2026-10-24T10:00:00+08:00'})
    task = client.post('/v1/mutations', json=create).json()['task']
    assert task['title'] == 'A thought' and task['status'] == 'todo'
    update = mutation(task['id'], 'update', task['version'], {'status': 'done', 'notes': None, 'dueAt': None})
    done = client.post('/v1/mutations', json=update).json()['task']
    assert done['completedAt'] and done['dueAt'] is None and done['notes'] is None
    assert client.get('/v1/tasks?status=done').json()['tasks'] == [done]
    delete = mutation(task['id'], 'delete', task['version'], {})
    deleted = client.post('/v1/mutations', json=delete).json()['task']
    assert deleted['deletedAt']
    assert client.get('/v1/tasks/' + task['id']).status_code == 404
    assert client.get('/v1/tasks').json()['tasks'] == []
    assert client.post('/v1/mutations', json=update | {'mutationId': str(uuid4())}).json()['error'] == 'deleted'
    assert client.post('/v1/mutations', json=create | {'mutationId': str(uuid4())}).json()['error'] == 'deleted'
    assert client.post('/v1/mutations', json=delete | {'mutationId': str(uuid4())}).status_code == 200
    assert client.get('/v1/export').json()['tasks'] == [deleted]


def test_idempotency_survives_restart(tmp_path):
    path = str(tmp_path / 'db.sqlite')
    write = Mutation.model_validate(mutation())
    result = Store(path).mutate(write)
    assert Store(path).mutate(write) == result
    assert len(Store(path).changes(0, 200)['changes']) == 1
    with pytest.raises(StoreError, match='idempotency_key_reused'):
        Store(path).mutate(write.model_copy(update={'taskId': uuid4()}))


def test_offline_create_delete_stays_deleted(client):
    task_id = str(uuid4())
    tombstone = mutation(task_id, 'delete', 0, {})
    assert client.post('/v1/mutations', json=tombstone).json()['task']['deletedAt']
    assert client.post('/v1/mutations', json=mutation(task_id)).json()['error'] == 'deleted'


def test_versions_and_incremental_pages(client):
    create = mutation()
    task = client.post('/v1/mutations', json=create).json()['task']
    stale = mutation(task['id'], 'update', 0, {'title': 'offline'})
    conflict = client.post('/v1/mutations', json=stale)
    assert conflict.status_code == 409 and conflict.json()['current'] == task
    current = client.post('/v1/mutations', json=stale | {'baseVersion': task['version']}).json()['task']
    first = client.get('/v1/changes?limit=1').json()
    assert first['changes'] == [task] and first['hasMore']
    second = client.get('/v1/changes', params={'after': first['cursor'], 'limit': 1}).json()
    assert second['changes'] == [current] and not second['hasMore']
    assert first['serverId'] == second['serverId']
    assert client.get('/v1/changes?after=99999').status_code == 409


def test_concurrent_cas(tmp_path):
    store = Store(str(tmp_path / 'db.sqlite'))
    task = store.mutate(Mutation.model_validate(mutation()))['task']
    def update(index):
        try:
            return store.mutate(Mutation.model_validate(mutation(task['id'], 'update', task['version'], {'title': str(index)})))
        except StoreError as error:
            return error.code
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(update, range(8)))
    assert sum(isinstance(r, dict) for r in results) == 1
    assert results.count('version_conflict') == 7


def test_backup_and_restore(tmp_path):
    store = Store(str(tmp_path / 'original.sqlite'))
    result = store.mutate(Mutation.model_validate(mutation()))
    backup = str(tmp_path / 'backup.sqlite')
    store.backup(backup)
    restored = Store(backup)
    assert restored.export()['tasks'] == [result['task']]
    assert restored.changes(0, 10)['serverId'] == store.changes(0, 10)['serverId']
    assert restored.mutate(Mutation.model_validate(mutation(key=uuid4())))
    with pytest.raises(ValueError):
        store.backup(backup)


@pytest.mark.parametrize('patch', [{'title': ''}, {'title': None}, {'status': None}, {'status': 'active'},
                                   {'priority': 'urgent'}, {'dueAt': '2026-10-24T10:00:00'}, {'unknown': 1}])
def test_invalid_payloads(client, patch):
    assert client.post('/v1/mutations', json=mutation(patch=patch)).status_code == 422
    assert client.get('/v1/tasks').json()['tasks'] == []


def test_rest_crud_and_filters(client):
    key = str(uuid4())
    data = {'title': 'Idea', 'status': 'backlog', 'dueAt': '2026-10-24T10:00:00Z'}
    result = client.post('/v1/tasks', json=data, headers={'Idempotency-Key': key})
    assert result.status_code == 201
    task = result.json()['task']
    assert client.post('/v1/tasks', json=data, headers={'Idempotency-Key': key}).json()['task'] == task
    assert client.get('/v1/tasks?status=backlog&due_before=2026-10-25T00:00:00Z').json()['tasks'] == [task]
    assert client.get('/v1/tasks?due_before=2026-10-23T00:00:00Z').json()['tasks'] == []
    assert client.get('/v1/tasks?limit=0').status_code == 422
    changed = client.patch('/v1/tasks/' + task['id'], params={'version': task['version'], 'mutationId': str(uuid4())}, json={'priority': 'high'}).json()['task']
    assert changed['priority'] == 'high'
    assert client.delete('/v1/tasks/' + task['id'], params={'version': changed['version'], 'mutationId': str(uuid4())}).status_code == 200


@pytest.mark.asyncio
async def test_real_streamable_http_mcp(tmp_path):
    import socket
    import uvicorn
    import httpx
    from mcp import ClientSession
    from mcp.client.streamable_http import streamablehttp_client
    app = create_app(str(tmp_path / 'mcp.sqlite'), TOKEN)
    sock = socket.socket()
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(app, log_level='critical', access_log=False))
    runner = asyncio.create_task(server.serve(sockets=[sock]))
    try:
        for _ in range(100):
            if server.started:
                break
            await asyncio.sleep(.02)
        assert server.started
        async with streamablehttp_client(f'http://127.0.0.1:{port}/mcp/', headers={'Authorization': 'Bearer ' + TOKEN}) as (read, write, _):
            async with ClientSession(read, write) as session:
                assert (await session.initialize()).serverInfo.name == 'nianbox'
                names = {tool.name for tool in (await session.list_tools()).tools}
                assert names == {'list_tasks', 'get_task', 'create_task', 'update_task', 'complete_task', 'delete_task'}
                result = await session.call_tool('create_task', {'title': 'MCP idea', 'notes': 'Hermes-compatible', 'status': 'backlog'})
                assert not result.isError
                task = json.loads(result.content[0].text)['task']
                async with httpx.AsyncClient(headers={'Authorization': 'Bearer ' + TOKEN}) as rest:
                    assert (await rest.get(f'http://127.0.0.1:{port}/v1/tasks/{task["id"]}')).json() == task
                updated = await session.call_tool('update_task', {'id': task['id'], 'version': task['version'], 'patch': {'priority': 'high'}})
                assert not updated.isError
                task = json.loads(updated.content[0].text)['task']
                done = await session.call_tool('complete_task', {'id': task['id'], 'version': task['version']})
                assert not done.isError
                task = json.loads(done.content[0].text)['task']
                assert task['status'] == 'done' and task['completedAt']
                assert not (await session.call_tool('get_task', {'id': task['id']})).isError
                assert not (await session.call_tool('list_tasks', {'status': 'done'})).isError
                assert not (await session.call_tool('delete_task', {'id': task['id'], 'version': task['version']})).isError
                assert (await session.call_tool('get_task', {'id': task['id']})).isError
    finally:
        server.should_exit = True
        await runner
        sock.close()
