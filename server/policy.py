"""Reject obvious credentials before they reach embeddings, SQL or history.

Heuristics are defense in depth; agents must never submit secrets.
"""
import hashlib
import re

PATTERNS = [
    r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    r'\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})\b',
    r'(?i)\b(?:password|passwort|passwd|pwd|api[_ -]?key|secret|access[_ -]?token|refresh[_ -]?token|authorization)\b\s*[=:]\s*\S+',
    r'(?i)\bBearer\s+[A-Za-z0-9._~+/-]{8,}',
    r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
    r'(?i)\b(?:postgres(?:ql)?|mysql|https?)://[^\s/:]+:[^\s/@]+@',
]

def safe_text(*values: str):
    for value in values:
        if not isinstance(value, str) or not value.strip():
            raise ValueError('Non-empty text required.')
        if any(re.search(pattern, value) for pattern in PATTERNS):
            raise ValueError('Possible credential detected. Remove all secrets before submitting.')

def validate(title, content, source, scope, kind):
    safe_text(title, content, source, scope, kind)
    if len(title) > 200 or len(content) > 4000 or len(source) > 1000:
        raise ValueError('Limits: title 200, content 4000, source 1000 characters. Split large knowledge into facts.')
    if not re.fullmatch(r'global|project:[A-Za-z0-9._/-]{1,120}', scope):
        raise ValueError('scope must be global or project:<stable-project-name>.')
    if kind not in {'fact', 'decision', 'preference', 'procedure', 'summary'}:
        raise ValueError('Invalid kind.')

def fingerprint(title, content):
    return hashlib.sha256((title.strip() + '\n' + content.strip()).encode()).hexdigest()
