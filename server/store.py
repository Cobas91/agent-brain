import os
import uuid
from pathlib import Path

import httpx
import psycopg
from psycopg.rows import dict_row
from policy import safe_text, validate, fingerprint

MODEL = os.getenv('EMBEDDING_MODEL', 'embeddinggemma')

def connect():
    return psycopg.connect(os.environ['DATABASE_URL'], row_factory=dict_row, connect_timeout=10)

def initialize():
    with connect() as db:
        # Serialize concurrent HTTP/stdio startup migrations.
        db.execute('SELECT pg_advisory_xact_lock(8765001)')
        db.execute(Path(__file__).with_name('schema.sql').read_text())
        db.execute("INSERT INTO brain_settings VALUES ('embedding_model', %s) ON CONFLICT DO NOTHING", (MODEL,))
        if db.execute("SELECT value FROM brain_settings WHERE key='embedding_model'").fetchone()['value'] != MODEL:
            raise RuntimeError('Embedding model changed. Re-embedding migration required.')

def embed(text):
    with httpx.Client(timeout=120) as client:
        response = client.post(os.getenv('OLLAMA_URL', 'http://ollama:11434') + '/api/embed',
                               json={'model': MODEL, 'input': text, 'truncate': False})
        if response.status_code != 200:
            raise RuntimeError('Embedding service failed; check model availability or shorten input.')
        vector = response.json()['embeddings'][0]
    if len(vector) != 768:
        raise RuntimeError('Expected 768 embedding dimensions.')
    return '[' + ','.join(str(float(v)) for v in vector) + ']'

FIELDS = 'id,scope,title,content,source,kind,revision,archived,created_at,updated_at'

def snapshot(db, memory_id, reason):
    db.execute('''INSERT INTO memory_history(memory_id,revision,snapshot,reason)
                  SELECT id,revision,to_jsonb(memories)-'embedding'-'fingerprint',%s
                  FROM memories WHERE id=%s''', (reason, memory_id))

def search(query, project=None, limit=5, min_similarity=0.25, max_chars=6000):
    safe_text(query)
    if len(query) > 4000 or not 1 <= limit <= 30 or not 0 <= min_similarity <= 1 or not 6000 <= max_chars <= 30000:
        raise ValueError('Invalid query length, limit or similarity.')
    scope = 'global' if not project else 'project:' + project.removeprefix('project:')
    validate('query', query, 'search', scope, 'fact')
    vector = embed(query)
    with connect() as db:
        rows = db.execute('''SELECT id,scope,title,content,source,revision,updated_at,
          1-(embedding <=> %s::vector) AS similarity
          FROM memories WHERE NOT archived AND scope IN ('global',%s)
          AND 1-(embedding <=> %s::vector) >= %s
          ORDER BY embedding <=> %s::vector LIMIT %s''',
          (vector, scope, vector, min_similarity, vector, limit)).fetchall()
    result, used = [], 0
    for row in rows:
        size = sum(len(row[key]) for key in ('title', 'content', 'source'))
        if used + size > max_chars:
            break
        row['similarity'] = round(row['similarity'], 3)
        result.append(row)
        used += size
    return result

def remember(title, content, source, scope='global', kind='fact'):
    validate(title, content, source, scope, kind)
    vector = embed(title + '\n' + content)
    with connect() as db:
        row = db.execute(f'''INSERT INTO memories(id,scope,title,content,source,kind,embedding,fingerprint)
          VALUES(%s,%s,%s,%s,%s,%s,%s::vector,%s)
          ON CONFLICT(scope,fingerprint) DO NOTHING RETURNING {FIELDS}''',
          (uuid.uuid4(), scope, title, content, source, kind, vector, fingerprint(title, content))).fetchone()
        if row:
            snapshot(db, row['id'], 'created')
            return {'created': True, 'memory': row}
        row = db.execute(f'SELECT {FIELDS} FROM memories WHERE scope=%s AND fingerprint=%s',
                         (scope, fingerprint(title, content))).fetchone()
        return {'created': False, 'memory': row}

def get(memory_id):
    with connect() as db:
        return db.execute(f'SELECT {FIELDS} FROM memories WHERE id=%s', (uuid.UUID(memory_id),)).fetchone()

def revise(memory_id, expected_revision, title, content, source, reason):
    safe_text(reason)
    if len(reason) > 1000:
        raise ValueError('Reason too long.')
    memory_id = uuid.UUID(memory_id)
    current = get(str(memory_id))
    if not current:
        raise ValueError('Memory not found.')
    validate(title, content, source, current['scope'], current['kind'])
    vector = embed(title + '\n' + content)
    with connect() as db:
        try:
            row = db.execute(f'''UPDATE memories SET title=%s,content=%s,source=%s,
                embedding=%s::vector,fingerprint=%s,revision=revision+1,updated_at=now()
                WHERE id=%s AND revision=%s AND NOT archived RETURNING {FIELDS}''',
                (title, content, source, vector, fingerprint(title, content), memory_id, expected_revision)).fetchone()
        except psycopg.errors.UniqueViolation:
            raise ValueError('Another memory already contains this exact knowledge.') from None
        if not row:
            raise ValueError('Revision conflict or archived entry. Read current memory before retrying.')
        snapshot(db, memory_id, reason)
        return row

def archive(memory_id, expected_revision, reason):
    safe_text(reason)
    if len(reason) > 1000:
        raise ValueError('Reason too long.')
    with connect() as db:
        row = db.execute(f'''UPDATE memories SET archived=true,revision=revision+1,updated_at=now()
            WHERE id=%s AND revision=%s AND NOT archived RETURNING {FIELDS}''',
            (uuid.UUID(memory_id), expected_revision)).fetchone()
        if not row:
            raise ValueError('Revision conflict, missing or already archived memory.')
        snapshot(db, row['id'], reason)
        return row

def history(memory_id):
    with connect() as db:
        return db.execute('SELECT revision,snapshot,reason,changed_at FROM memory_history WHERE memory_id=%s ORDER BY revision',
                          (uuid.UUID(memory_id),)).fetchall()

def restore(memory_id, target_revision, expected_revision, reason):
    safe_text(reason)
    if len(reason) > 1000:
        raise ValueError('Reason too long.')
    with connect() as db:
        entry = db.execute('SELECT snapshot FROM memory_history WHERE memory_id=%s AND revision=%s',
                           (uuid.UUID(memory_id), target_revision)).fetchone()
    if not entry:
        raise ValueError('Historical revision not found.')
    old = entry['snapshot']
    validate(old['title'], old['content'], old['source'], old['scope'], old['kind'])
    vector = embed(old['title'] + '\n' + old['content'])
    with connect() as db:
        row = db.execute(f'''UPDATE memories SET title=%s,content=%s,source=%s,embedding=%s::vector,
            fingerprint=%s,archived=%s,revision=revision+1,updated_at=now()
            WHERE id=%s AND revision=%s RETURNING {FIELDS}''',
            (old['title'], old['content'], old['source'], vector, fingerprint(old['title'], old['content']),
             old['archived'], uuid.UUID(memory_id), expected_revision)).fetchone()
        if not row:
            raise ValueError('Revision conflict. Read current memory before retrying.')
        snapshot(db, row['id'], reason)
        return row
