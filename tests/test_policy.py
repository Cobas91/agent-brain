import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
import pytest
from policy import safe_text, validate

@pytest.mark.parametrize('text', [
    'password=secret', 'Passwort: geheim', 'api_key="value"',
    'Authorization: Bearer abcdefghijklmnop',
    'postgresql://user:secret@host/db',
    '-----BEGIN PRIVATE KEY-----', 'ghp_' + 'a'*30,
])
def test_reject_credentials(text):
    with pytest.raises(ValueError): safe_text(text)

def test_regular_knowledge():
    validate('Preference', 'Never save passwords.', 'User request, 2026-10-08', 'global', 'preference')

def test_scope_and_size():
    with pytest.raises(ValueError): validate('a','b','c','arbitrary','fact')
    with pytest.raises(ValueError): validate('a','x'*4001,'c','global','fact')
