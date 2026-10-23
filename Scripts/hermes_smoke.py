#!/usr/bin/env python3
"""Run with the installed Hermes Python environment; never changes the real Hermes profile.

Set HERMES_HOME to an isolated test directory, NIANBOX_URL and NIANBOX_API_TOKEN.
Pass --source to the existing Hermes checkout and --fixture to an ignored output JSON.
"""
import argparse
import asyncio
import json
import logging
import os
from pathlib import Path
import sys
from uuid import uuid4

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, type=Path)
parser.add_argument('--fixture', required=True, type=Path)
args = parser.parse_args()
if not os.environ.get('HERMES_HOME'):
    parser.error('HERMES_HOME must point to an isolated test directory')
sys.dont_write_bytecode = True
sys.path.insert(0, str(args.source.resolve()))
logging.basicConfig(level=logging.ERROR)

async def main():
    from tools import mcp_tool
    from tools.mcp_tool_config import _interpolate_env_vars
    import httpx
    assert mcp_tool._ensure_mcp_sdk() and mcp_tool._MCP_HTTP_AVAILABLE
    url = os.environ['NIANBOX_URL'].rstrip('/')
    token = os.environ['NIANBOX_API_TOKEN']
    config = _interpolate_env_vars({'url': url + '/mcp/', 'headers': {'Authorization': 'Bearer ${NIANBOX_API_TOKEN}'},
                                    'strict_redirect_headers': True, 'connect_timeout': 10,
                                    'sampling': {'enabled': False}, 'elicitation': {'enabled': False}})
    assert config['headers']['Authorization'] == 'Bearer ' + token
    server = mcp_tool.MCPServerTask('nianbox')
    try:
        await asyncio.wait_for(server.start(config), timeout=20)
        names = {tool.name for tool in server._tools}
        assert names == {'list_tasks', 'get_task', 'create_task', 'update_task', 'complete_task', 'delete_task'}, names
        async def call(name, arguments):
            reply = await asyncio.wait_for(server.session.call_tool(name, arguments), timeout=10)
            assert not getattr(reply, 'is_error', getattr(reply, 'isError', False)), name + ' failed'
            return json.loads(reply.content[0].text)
        task_id, key = str(uuid4()), str(uuid4())
        title = 'Hermes integration ' + task_id[:8]
        task = (await call('create_task', {'id': task_id, 'mutationId': key, 'title': title,
                     'notes': 'Captured through the installed Hermes native MCP client',
                     'dueAt': '2026-12-01T09:00:00+08:00'}))['task']
        assert (await call('create_task', {'id': task_id, 'mutationId': key, 'title': title,
                     'notes': 'Captured through the installed Hermes native MCP client',
                     'dueAt': '2026-12-01T09:00:00+08:00'}))['task'] == task
        assert (await call('get_task', {'id': task_id}))['id'] == task_id
        task = (await call('update_task', {'id': task_id, 'version': task['version'], 'patch': {'priority': 'high'}}))['task']
        listed = await call('list_tasks', {'status': 'todo'})
        assert any(t['id'] == task_id for t in listed['tasks'])
        # Exercise completion and deletion on a separate disposable task; preserve the fixture for Mac import.
        disposable = (await call('create_task', {'title': 'Hermes completion/delete probe'}))['task']
        disposable = (await call('complete_task', {'id': disposable['id'], 'version': disposable['version']}))['task']
        assert disposable['completedAt'] and disposable['status'] == 'done'
        assert (await call('delete_task', {'id': disposable['id'], 'version': disposable['version']}))['task']['deletedAt']
        async with httpx.AsyncClient(headers={'Authorization': 'Bearer ' + token}) as rest:
            response = await rest.get(url + '/v1/tasks/' + task_id)
            response.raise_for_status()
            assert response.json() == task
        args.fixture.parent.mkdir(parents=True, exist_ok=True)
        args.fixture.write_text(json.dumps({'url': url, 'token': token, 'task': task}))
        args.fixture.chmod(0o600)
        print('PASS: installed Hermes native HTTP client discovered six tools, executed CRUD/completion, and REST read the same persisted task')
        print('Fixture task:', task_id)
    finally:
        await server.shutdown()

asyncio.run(main())
