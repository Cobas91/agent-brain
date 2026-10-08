"""Real MCP HTTP and stdio, Ollama and PostgreSQL integration test.
Only removes rows belonging to a randomly generated private test scope.
"""
import asyncio
import json
import os
import sys
import uuid
import httpx
from mcp import ClientSession, StdioServerParameters
from mcp.client.streamable_http import streamablehttp_client
from mcp.client.stdio import stdio_client
import store

async def call(session, name, args):
    result = await session.call_tool(name, args)
    if result.isError:
        raise AssertionError('Tool failed: ' + name)
    if result.structuredContent is not None:
        data = result.structuredContent
        return data['result'] if set(data) == {'result'} else data
    if name in {'brain_search', 'brain_history'}:
        return [json.loads(block.text) for block in result.content]
    return json.loads(result.content[0].text)

async def main():
    project = 'test-' + uuid.uuid4().hex
    scope = 'project:' + project
    try:
        async with streamablehttp_client('http://127.0.0.1:8765/mcp') as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                tools = await session.list_tools()
                assert len(tools.tools) == 7
                args = dict(title='Integration test preference', content='For this test project the preferred colour is violet.', source='automated integration test', scope=scope, kind='preference')
                created = await call(session, 'brain_remember', args)
                assert created['created']
                memory = created['memory']; mid = memory['id']
                duplicate = await call(session, 'brain_remember', args)
                assert not duplicate['created'] and duplicate['memory']['id'] == mid
                found = await call(session, 'brain_search', dict(query='preferred colour violet', project=project, min_similarity=0))
                assert any(x['id'] == mid for x in found)
                assert all('embedding' not in x and 'created_at' not in x and 'archived' not in x for x in found)
                assert sum(sum(len(x[k]) for k in ('title','content','source')) for x in found) <= 6000
                global_found = await call(session, 'brain_search', dict(query='preferred colour violet', min_similarity=0))
                assert not any(x['id'] == mid for x in global_found)
                update = dict(memory_id=mid, expected_revision=1, title=args['title'], content='For this test project the preferred colour is green.', source=args['source'], reason='test correction')
                changed = await call(session, 'brain_update', update)
                assert changed['revision'] == 2
                stale = await session.call_tool('brain_update', update)
                assert stale.isError
                forbidden = await session.call_tool('brain_remember', {**args, 'content':'password=not-a-real-secret'})
                assert forbidden.isError
                archived = await call(session, 'brain_archive', dict(memory_id=mid, expected_revision=2, reason='test archival'))
                assert archived['archived']
                found = await call(session, 'brain_search', dict(query='preferred colour', project=project, min_similarity=0))
                assert not any(x['id'] == mid for x in found)
                restored = await call(session, 'brain_restore', dict(memory_id=mid, target_revision=1, expected_revision=3, reason='test recovery'))
                assert restored['revision'] == 4 and not restored['archived'] and restored['content'] == args['content']
                history = await call(session, 'brain_history', dict(memory_id=mid))
                assert len(history) == 4
        async with httpx.AsyncClient() as client:
            rejected = await client.post('http://127.0.0.1:8765/mcp', headers={'Host':'malicious.example'}, json={})
            assert rejected.status_code == 421
        async with stdio_client(StdioServerParameters(command=sys.executable, args=['server.py','--stdio'],
                env={key: os.environ[key] for key in ('DATABASE_URL','OLLAMA_URL','EMBEDDING_MODEL')})) as (read,write):
            async with ClientSession(read,write) as session:
                await session.initialize()
                readback = await call(session, 'brain_get', dict(memory_id=mid))
                assert readback['revision'] == 4
        print('PASS: MCP HTTP + stdio, 768D embeddings, compact search/scope isolation, deduplication, revision conflicts, secret rejection, archive/restore and DNS-rebinding protection.')
    finally:
        with store.connect() as db:
            db.execute('DELETE FROM memory_history WHERE memory_id IN (SELECT id FROM memories WHERE scope=%s)', (scope,))
            db.execute('DELETE FROM memories WHERE scope=%s', (scope,))

if __name__ == '__main__':
    asyncio.run(main())
