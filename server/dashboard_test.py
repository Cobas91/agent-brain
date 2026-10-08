"""Checks the real dashboard with isolated fixture rows; never alters user entries."""
import uuid
import httpx
import store

def main():
    scope = 'project:dashboard-test-' + uuid.uuid4().hex
    ids = [uuid.uuid4() for _ in range(28)]
    try:
        with store.connect() as db:
            vector = '[' + ','.join(['1'] + ['0'] * 767) + ']'
            for i, memory_id in enumerate(ids):
                title = '<script>fixture_' + str(i) + '%</script>'
                db.execute('''INSERT INTO memories(id,scope,title,content,source,kind,embedding,fingerprint,archived)
                    VALUES(%s,%s,%s,%s,%s,%s,%s::vector,%s,%s)''',
                    (memory_id, scope, title, 'Isolated dashboard fixture.', 'Local test', 'fact', vector, str(memory_id), i == 27))
                store.snapshot(db, memory_id, 'created')
        with httpx.Client(base_url='http://127.0.0.1:8080') as client:
            assert client.get('/health').status_code == 200
            overview = client.get('/api/overview').json()
            assert any(x['scope'] == scope and x['total'] == 28 for x in overview['scopes'])
            response = client.get('/api/memories', params={'scope':scope})
            assert response.status_code == 200 and 'no-store' in response.headers['cache-control']
            result = response.json()
            assert result['total'] == 27 and len(result['items']) == 24
            assert all('embedding' not in x and 'fingerprint' not in x for x in result['items'])
            assert len(client.get('/api/memories',params={'scope':scope,'page':2}).json()['items']) == 3
            assert client.get('/api/memories',params={'scope':scope,'status':'archived'}).json()['total'] == 1
            assert client.get('/api/memories',params={'scope':scope,'q':'fixture_26%'}).json()['total'] == 1
            assert client.get('/api/memories',params={'scope':scope,'kind':'preference'}).json()['total'] == 0
            assert client.get('/api/memories',params={'scope':scope,'q':"' OR true --"}).json()['total'] == 0
            detail = client.get('/api/memories/' + str(ids[0])).json()
            assert detail['memory']['content'] == 'Isolated dashboard fixture.' and len(detail['history']) == 1
            assert 'embedding' not in detail['memory']
            assert client.get('/api/memories/not-a-uuid').status_code == 400
            assert client.get('/api/memories/' + str(uuid.uuid4())).status_code == 404
            assert client.get('/api/memories',params={'page_size':101}).status_code == 400
            assert client.get('/api/memories',params={'status':'wrong'}).status_code == 400
            assert client.post('/api/memories',json={}).status_code == 405
            assert client.get('/api/overview',headers={'Host':'untrusted.example'}).status_code == 400
            html = client.get('/')
            assert html.status_code == 200 and 'Wissensbibliothek' in html.text
            assert "script-src 'self'" in html.headers['content-security-policy']
            assert client.get('/assets/app.js').status_code == 200
            graph = client.get('/api/map',params={'scope':scope,'threshold':0.9}).json()
            graph_ids = {item['id'] for item in graph['nodes']}
            assert str(ids[0]) in graph_ids and str(ids[27]) not in graph_ids
            assert all('embedding' not in item for item in graph['nodes'])
            fixture_ids = {str(value) for value in ids[:27]}
            fixture_edges = [edge for edge in graph['edges'] if edge['source'] in fixture_ids and edge['target'] in fixture_ids]
            assert fixture_edges and all(edge['similarity'] == 1 for edge in fixture_edges)
            assert len({(x['source'],x['target']) for x in graph['edges']}) == len(graph['edges'])
            focused = client.get('/api/map',params={'scope':scope,'limit':3,'focus_ids':str(ids[0])}).json()
            assert focused['truncated'] and len(focused['nodes']) == 3 and str(ids[0]) in {x['id'] for x in focused['nodes']}
            assert client.get('/api/map',params={'threshold':'nan'}).status_code == 400
            assert client.get('/api/map',params={'focus_ids':'bad-id'}).status_code == 400
            assert client.get('/api/map',params={'limit':201}).status_code == 400
            assert client.post('/api/query',json={'query':'password=synthetic-test-value'}).status_code == 400
            assert client.post('/api/query',json={'query':'test','limit':31}).status_code == 400
            assert client.post('/api/query',json=[]).status_code == 400
            question = 'Kompakte Wissenseinträge ohne Informationsverlust'
            preview = client.post('/api/query',json={'query':question,'project':scope.removeprefix('project:')}).json()
            expected = store.search(question,scope.removeprefix('project:'))
            assert [entry['id'] for entry in preview['results']] == [str(entry['id']) for entry in expected]
            assert preview['used_chars'] == sum(len(entry[key]) for entry in expected for key in ('title','content','source'))
            assert preview['max_chars'] == 6000 and preview['limit'] == 5
            budget_question = 'Temporary context-budget fixture ' + scope
            real_vector = store.embed(budget_question)
            with store.connect() as db:
                for memory_id in ids[:3]:
                    db.execute('UPDATE memories SET embedding=%s::vector,content=%s WHERE id=%s',
                        (real_vector,'x'*2400,memory_id))
            limited = client.post('/api/query',json={'query':budget_question,'project':scope.removeprefix('project:'),'min_similarity':0.99}).json()
            assert len(limited['results']) == 2 and limited['used_chars'] <= 6000
            assert all(len(entry['content']) == 2400 for entry in limited['results'])
            assert {entry['id'] for entry in limited['results']} <= {str(value) for value in ids[:3]}
            global_only = client.post('/api/query',json={'query':budget_question,'min_similarity':0.99}).json()
            assert not any(entry['id'] in fixture_ids for entry in global_only['results'])
        print('PASS: dashboard browsing, similarity map/caps/focus, archive exclusion, safe query validation and parity with MCP retrieval.')
    finally:
        with store.connect() as db:
            db.execute('DELETE FROM memory_history WHERE memory_id IN (SELECT id FROM memories WHERE scope=%s)', (scope,))
            db.execute('DELETE FROM memories WHERE scope=%s', (scope,))

if __name__ == '__main__':
    main()
