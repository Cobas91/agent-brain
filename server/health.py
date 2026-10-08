import store
with store.connect() as db:
    db.execute('SELECT 1 FROM memories LIMIT 1')
store.embed('health check')
