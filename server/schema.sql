CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE IF NOT EXISTS brain_settings (
  key text PRIMARY KEY, value text NOT NULL
);
CREATE TABLE IF NOT EXISTS memories (
  id uuid PRIMARY KEY,
  scope text NOT NULL,
  title text NOT NULL,
  content text NOT NULL,
  source text NOT NULL,
  kind text NOT NULL,
  embedding vector(768) NOT NULL,
  fingerprint text NOT NULL,
  revision integer NOT NULL DEFAULT 1,
  archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(scope, fingerprint)
);
CREATE INDEX IF NOT EXISTS memories_embedding ON memories USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS memories_scope ON memories(scope);
CREATE TABLE IF NOT EXISTS memory_history (
  memory_id uuid NOT NULL REFERENCES memories(id),
  revision integer NOT NULL,
  snapshot jsonb NOT NULL,
  reason text NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(memory_id, revision)
);
