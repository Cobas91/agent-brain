"""Local read-only knowledge browser, similarity map and MCP retrieval preview."""
import datetime
import json
import math
import uuid
from contextlib import contextmanager
from pathlib import Path

import psycopg
import httpx
from starlette.applications import Starlette
from starlette.concurrency import run_in_threadpool
from starlette.middleware import Middleware
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.responses import FileResponse, JSONResponse
from starlette.routing import Mount, Route
from starlette.staticfiles import StaticFiles
import store

ASSETS = Path(__file__).with_name('dashboard')

def json_default(value):
    if isinstance(value, (uuid.UUID, datetime.datetime, datetime.date)):
        return str(value) if isinstance(value, uuid.UUID) else value.isoformat()
    raise TypeError(type(value).__name__)

class BrainJSONResponse(JSONResponse):
    def render(self, content):
        return json.dumps(content, default=json_default, ensure_ascii=False, allow_nan=False).encode('utf-8')

@contextmanager
def read_db():
    with store.connect() as db:
        db.execute('SET TRANSACTION READ ONLY')
        db.execute("SET LOCAL statement_timeout = '5s'")
        yield db

def number(params, name, default, minimum, maximum):
    value = int(params.get(name, default))
    if not minimum <= value <= maximum:
        raise ValueError('Invalid pagination.')
    return value

def index(request):
    return FileResponse(ASSETS / 'index.html')

def health(request):
    with read_db() as db:
        db.execute('SELECT 1 FROM memories LIMIT 1')
    return BrainJSONResponse({'status': 'ok'})

def overview(request):
    with read_db() as db:
        stats = db.execute('''SELECT count(*) AS total,
            count(*) FILTER (WHERE NOT archived) AS active,
            count(*) FILTER (WHERE archived) AS archived,
            count(DISTINCT scope) FILTER (WHERE scope <> 'global') AS projects,
            max(updated_at) AS latest_update FROM memories''').fetchone()
        scopes = db.execute('''SELECT scope,count(*) AS total,
            count(*) FILTER (WHERE NOT archived) AS active FROM memories GROUP BY scope ORDER BY scope''').fetchall()
        kinds = db.execute('SELECT kind,count(*) AS total FROM memories GROUP BY kind ORDER BY kind').fetchall()
    return BrainJSONResponse({'stats': stats, 'scopes': scopes, 'kinds': kinds})

def memories(request):
    params = request.query_params
    try:
        page = number(params, 'page', 1, 1, 1000000)
        size = number(params, 'page_size', 24, 1, 100)
        query = params.get('q', '').strip()
        scope = params.get('scope', '')
        kind = params.get('kind', '')
        status = params.get('status', 'active')
        sort = params.get('sort', 'updated')
        if len(query) > 500 or len(scope) > 140 or kind not in {'', 'fact','decision','preference','procedure','summary'}:
            raise ValueError('Invalid filter.')
        if status not in {'active','archived','all'} or sort not in {'updated','created','title'}:
            raise ValueError('Invalid filter.')
    except (ValueError, TypeError):
        return BrainJSONResponse({'error': 'Die Suchparameter sind ungültig.'}, status_code=400)
    conditions, values = [], []
    if status != 'all':
        conditions.append('archived=%s'); values.append(status == 'archived')
    if scope:
        conditions.append('scope=%s'); values.append(scope)
    if kind:
        conditions.append('kind=%s'); values.append(kind)
    if query:
        # Escape LIKE wildcards; search treats arbitrary user input as literal text.
        literal = query.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
        conditions.append("(title ILIKE %s OR content ILIKE %s OR source ILIKE %s)")
        values.extend(['%' + literal + '%'] * 3)
    where = ' AND '.join(conditions) if conditions else 'true'
    order = {'updated':'updated_at DESC,id','created':'created_at DESC,id','title':'lower(title),id'}[sort]
    with read_db() as db:
        total = db.execute(f'SELECT count(*) AS total FROM memories WHERE {where}', values).fetchone()['total']
        rows = db.execute(f'''SELECT id,scope,title,left(content,260) AS preview,kind,
            revision,archived,created_at,updated_at FROM memories WHERE {where}
            ORDER BY {order} LIMIT %s OFFSET %s''', values + [size, (page-1)*size]).fetchall()
    return BrainJSONResponse({'items': rows, 'total': total, 'page': page, 'page_size': size})

def detail(request):
    try:
        memory_id = uuid.UUID(request.path_params['memory_id'])
    except ValueError:
        return BrainJSONResponse({'error':'Ungültige Eintrags-ID.'}, status_code=400)
    with read_db() as db:
        memory = db.execute(f'SELECT {store.FIELDS} FROM memories WHERE id=%s', (memory_id,)).fetchone()
        if memory is None:
            return BrainJSONResponse({'error':'Dieser Eintrag wurde nicht gefunden.'}, status_code=404)
        history = db.execute('''SELECT revision,snapshot,reason,changed_at FROM memory_history
            WHERE memory_id=%s ORDER BY revision DESC''', (memory_id,)).fetchall()
    return BrainJSONResponse({'memory': memory, 'history': history})

def knowledge_map(request):
    params = request.query_params
    try:
        limit = number(params, 'limit', 200, 1, 200)
        threshold = float(params.get('threshold', '0.15'))
        scope = params.get('scope', '')
        focus = [uuid.UUID(value) for value in params.get('focus_ids', '').split(',') if value]
        if len(focus) > 30 or len(scope) > 140 or not math.isfinite(threshold) or not 0 <= threshold <= 1:
            raise ValueError('Invalid map parameters.')
    except (ValueError, TypeError):
        return BrainJSONResponse({'error':'Die Kartenparameter sind ungültig.'}, status_code=400)
    conditions, values = ['NOT archived'], []
    if scope:
        conditions.append("scope IN ('global',%s)"); values.append(scope)
    where = ' AND '.join(conditions)
    with read_db() as db:
        total = db.execute(f'SELECT count(*) AS total FROM memories WHERE {where}', values).fetchone()['total']
        nodes = db.execute(f'''SELECT id,title,scope,kind,revision FROM memories WHERE {where}
            ORDER BY CASE WHEN id=ANY(%s::uuid[]) THEN 0 ELSE 1 END,updated_at DESC,id LIMIT %s''',
            values + [focus, limit]).fetchall()
        ids = [entry['id'] for entry in nodes]
        pairs = db.execute('''SELECT a.id AS source,b.id AS target,
            1-(a.embedding <=> b.embedding) AS similarity FROM memories a JOIN memories b ON a.id<b.id
            WHERE a.id=ANY(%s::uuid[]) AND b.id=ANY(%s::uuid[])''', (ids, ids)).fetchall() if len(ids) > 1 else []
    neighbours = {entry['id']: [] for entry in nodes}
    for pair in pairs:
        if pair['similarity'] >= threshold:
            neighbours[pair['source']].append(pair)
            neighbours[pair['target']].append(pair)
    edges = {}
    for candidates in neighbours.values():
        for pair in sorted(candidates, key=lambda edge: (-edge['similarity'],str(edge['source']),str(edge['target'])))[:4]:
            edges[(pair['source'],pair['target'])] = {**pair, 'similarity':round(pair['similarity'],4)}
    return BrainJSONResponse({'nodes':nodes,'edges':list(edges.values()),'total':total,
        'limit':limit,'threshold':threshold,'neighbours_per_node':4,'truncated':total > len(nodes)})

async def retrieval_preview(request):
    try:
        body = await request.json()
        if not isinstance(body, dict):
            raise ValueError('Expected object.')
        question = body.get('query')
        project = body.get('project') or None
        limit = body.get('limit',5)
        threshold = body.get('min_similarity',0.25)
        max_chars = body.get('max_chars',6000)
        if not isinstance(question,str) or not question.strip() or (project is not None and not isinstance(project,str)):
            raise ValueError('Invalid question.')
        if type(limit) is not int or type(max_chars) is not int or type(threshold) not in (int,float) or not math.isfinite(threshold):
            raise ValueError('Invalid parameters.')
        # Exactly the MCP function: no separate ranking or truncation layer.
        results = await run_in_threadpool(store.search,question,project,limit,threshold,max_chars)
    except (ValueError, TypeError, json.JSONDecodeError):
        return BrainJSONResponse({'error':'Ungültige Frage oder Suchparameter. Keine Zugangsdaten eingeben; maximal 4000 Zeichen.'}, status_code=400)
    except (RuntimeError, httpx.HTTPError):
        return BrainJSONResponse({'error':'Die Embedding-Suche ist gerade nicht verfügbar. Bitte erneut versuchen.'}, status_code=503)
    return BrainJSONResponse({'results':results,'query':question,'project':project,'limit':limit,
        'min_similarity':threshold,'max_chars':max_chars,
        'used_chars':sum(len(item[key]) for item in results for key in ('title','content','source')),
        'searched_at':datetime.datetime.now(datetime.timezone.utc)})

async def unavailable(request, exc):
    # Do not expose connection strings, SQL, or exception details to the browser.
    return BrainJSONResponse({'error':'Der Wissensspeicher ist gerade nicht erreichbar. Bitte erneut versuchen.'}, status_code=503)

class PrivacyHeaders:
    def __init__(self, app):
        self.app = app
    async def __call__(self, scope, receive, send):
        async def send_headers(message):
            if message['type'] == 'http.response.start':
                message.setdefault('headers', []).extend([
                    (b'cache-control', b'no-store'),
                    (b'x-content-type-options', b'nosniff'),
                    (b'referrer-policy', b'no-referrer'),
                    (b'content-security-policy', b"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"),
                ])
            await send(message)
        await self.app(scope, receive, send_headers)

app = Starlette(routes=[
    Route('/', index), Route('/health', health),
    Route('/api/overview', overview), Route('/api/memories', memories),
    Route('/api/map', knowledge_map), Route('/api/query', retrieval_preview, methods=['POST']),
    Route('/api/memories/{memory_id}', detail),
    Mount('/assets', StaticFiles(directory=ASSETS), name='assets'),
], middleware=[Middleware(PrivacyHeaders), Middleware(TrustedHostMiddleware, allowed_hosts=['localhost','127.0.0.1'])],
    exception_handlers={psycopg.Error: unavailable})
