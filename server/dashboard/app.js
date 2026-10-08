'use strict';
const $ = id => document.getElementById(id);
const kinds = { fact: 'Fakt', decision: 'Entscheidung', preference: 'Präferenz', procedure: 'Vorgehensweise', summary: 'Zusammenfassung' };
const state = { page: 1, scope: '', status: 'active', selected: null, overview: null, request: 0, busy: false };
const date = value => value ? new Date(value).toLocaleDateString('de-DE', { timeZone: 'Europe/Berlin', day: '2-digit', month: 'short', year: 'numeric' }) : '—';
const time = value => value ? new Date(value).toLocaleTimeString('de-DE', { timeZone: 'Europe/Berlin', hour: '2-digit', minute: '2-digit' }) + ' Uhr' : '';
const scopeLabel = scope => scope === 'global' ? 'Global' : scope.replace(/^project:/, '');
function node(tag, cls, text) { const item = document.createElement(tag); if (cls) item.className = cls; if (text !== undefined) item.textContent = text; return item; }
async function api(path, options = {}) {
  const response = await fetch(path, { cache: 'no-store', ...options });
  let data; try { data = await response.json(); } catch { throw new Error('Die Antwort konnte nicht geladen werden. Bitte erneut versuchen.'); }
  if (!response.ok) throw new Error(data.error || 'Die Verbindung zum Wissensspeicher ist unterbrochen.');
  return data;
}
function connection(ok) {
  $('connection-dot').classList.toggle('offline', !ok);
  $('connection-text').replaceChildren(document.createTextNode(ok ? 'Brain ist verbunden' : 'Verbindung unterbrochen'), node('span', '', 'Wissen bleibt auf deinem PC'));
}
function updateOverview(data) {
  state.overview = data;
  $('stat-active').textContent = data.stats.active.toLocaleString('de-DE');
  $('stat-projects').textContent = data.stats.projects;
  $('stat-archived').textContent = data.stats.archived;
  $('stat-latest').textContent = date(data.stats.latest_update);
  $('stat-latest-time').textContent = data.stats.latest_update ? time(data.stats.latest_update) : 'Noch keine Aktivität';
  $('nav-active').textContent = data.stats.active;
  $('nav-archived').textContent = data.stats.archived;
  $('scope-count').textContent = data.scopes.length;
  const buttons = [{ scope: '', total: data.stats.total }, ...data.scopes].map(item => {
    const button = node('button', 'scope-button' + (state.scope === item.scope ? ' selected' : ''));
    button.dataset.scope = item.scope;
    button.setAttribute('aria-pressed', String(state.scope === item.scope));
    button.append(node('span', 'scope-name', item.scope ? scopeLabel(item.scope) : 'Alle Bereiche'), node('span', 'nav-count', item.total));
    button.addEventListener('click', () => { state.scope = item.scope; state.page = 1; updateOverview(state.overview); window.brainMap?.scopeChanged(item.scope); load(); });
    return button;
  });
  $('scope-nav').replaceChildren(...buttons);
  window.brainMap?.updateOverview(data);
}
function renderCards(data) {
  const filtered = Boolean($('search').value.trim() || $('kind').value || state.scope);
  $('result-count').textContent = `${data.total} ${data.total === 1 ? 'Eintrag' : 'Einträge'}${state.scope ? ' · ' + scopeLabel(state.scope) : ''}`;
  $('empty').hidden = data.items.length !== 0;
  $('empty-title').textContent = filtered ? 'Kein passendes Wissen gefunden.' : state.status === 'archived' ? 'Dein Archiv ist noch leer.' : 'Hier entsteht dein Wissen.';
  $('empty-description').textContent = filtered ? 'Versuche einen anderen Suchbegriff oder passe die Filter an.' : state.status === 'archived' ? 'Archivierte Einträge bleiben hier mit ihrer Änderungshistorie erhalten.' : 'Sobald ein Agent hilfreiches Wissen speichert, erscheint es hier.';
  $('reset-filters').hidden = !filtered;
  $('memory-grid').replaceChildren(...data.items.map(memory => {
    const card = node('button', 'memory-card'); card.type = 'button'; card.dataset.memoryId = memory.id;
    const top = node('div', 'card-top');
    top.append(node('span', 'kind-badge ' + memory.kind, kinds[memory.kind] || memory.kind), node('span', 'revision', `v${memory.revision}`));
    const bottom = node('div', 'card-bottom');
    bottom.append(node('span', 'card-scope', scopeLabel(memory.scope)), node('span', 'card-date', date(memory.updated_at)), node('span', 'card-arrow', '↗'));
    card.append(top, node('h3', '', memory.title), node('p', 'card-preview', memory.preview), bottom);
    card.addEventListener('click', () => openMemory(memory.id));
    return card;
  }));
  const pages = Math.max(1, Math.ceil(data.total / data.page_size));
  $('pagination').hidden = pages <= 1;
  $('page-number').textContent = `Seite ${data.page} von ${pages}`;
  $('previous').disabled = state.page <= 1; $('next').disabled = state.page >= pages;
}
let activeController;
async function load({ quiet = false } = {}) {
  const serial = ++state.request;
  activeController?.abort(); activeController = new AbortController();
  state.busy = true;
  if (!quiet) $('memory-grid').setAttribute('aria-busy', 'true');
  $('refresh').disabled = true;
  const params = new URLSearchParams({ page: state.page, status: state.status, scope: state.scope, kind: $('kind').value, sort: $('sort').value, q: $('search').value.trim() });
  try {
    const [overview, data] = await Promise.all([api('/api/overview', { signal: activeController.signal }), api('/api/memories?' + params, { signal: activeController.signal })]);
    if (serial !== state.request) return;
    if (data.total && data.items.length === 0 && state.page > 1) { state.page = 1; return load(); }
    updateOverview(overview); renderCards(data); connection(true); $('error-banner').hidden = true;
    $('last-sync').textContent = 'Stand ' + time(new Date().toISOString());
  } catch (error) {
    if (serial !== state.request || error.name === 'AbortError') return;
    connection(false); $('error-banner').textContent = error.message; $('error-banner').hidden = false;
    $('result-count').textContent = 'Aktualisierung fehlgeschlagen';
    if ($('memory-grid').querySelector('.skeleton')) $('memory-grid').replaceChildren();
  } finally {
    if (serial === state.request) { state.busy = false; $('memory-grid').setAttribute('aria-busy', 'false'); $('refresh').disabled = false; }
  }
}
function metaItem(label, value, wide = false) {
  const entry = node('div', wide ? 'wide' : ''); entry.append(node('dt', '', label), node('dd', '', value)); return entry;
}
let detailRequest = 0;
async function openMemory(id) {
  const serial = ++detailRequest; state.selected = id;
  $('detail-content').replaceChildren(node('h2', '', 'Eintrag wird geladen …'));
  $('detail-content').firstChild.id = 'detail-title';
  if (!$('detail-dialog').open) $('detail-dialog').showModal();
  history.replaceState(null, '', '#memory=' + encodeURIComponent(id));
  try {
    const data = await api('/api/memories/' + encodeURIComponent(id));
    if (serial !== detailRequest || !$('detail-dialog').open) return;
    const memory = data.memory;
    const badges = node('div', 'detail-heading'); badges.append(node('span', 'kind-badge ' + memory.kind, kinds[memory.kind] || memory.kind));
    if (memory.archived) badges.append(node('span', 'archived-badge', 'Archiviert'));
    const title = node('h2', '', memory.title); title.id = 'detail-title';
    const meta = node('dl', 'detail-meta');
    meta.append(metaItem('Bereich', scopeLabel(memory.scope)), metaItem('Version', 'v' + memory.revision), metaItem('Erstellt', date(memory.created_at) + ' · ' + time(memory.created_at)), metaItem('Geändert', date(memory.updated_at) + ' · ' + time(memory.updated_at)), metaItem('Quelle', memory.source, true));
    const actions = node('div', 'detail-actions');
    const copy = node('button', 'secondary-button', 'Inhalt kopieren');
    copy.addEventListener('click', async () => { try { await navigator.clipboard.writeText(memory.content); toast('Inhalt kopiert'); } catch { toast('Kopieren nicht möglich. Text bitte markieren.'); } });
    actions.append(copy);
    const historyTitle = node('h3', 'history-title', `Änderungshistorie · ${data.history.length} ${data.history.length === 1 ? 'Version' : 'Versionen'}`);
    const timeline = data.history.map(version => {
      const item = node('article', 'history-item'); const head = node('header');
      head.append(node('strong', '', 'Version ' + version.revision + (version.revision === memory.revision ? ' · Aktuell' : '')), node('time', '', date(version.changed_at) + ' · ' + time(version.changed_at)));
      const details = node('details'); details.append(node('summary', '', 'Gespeicherte Version ansehen'));
      const snapshot = node('div', 'version-text');
      snapshot.append(node('strong', '', version.snapshot.title), node('p', '', version.snapshot.content), node('p', 'version-source', 'Quelle: ' + version.snapshot.source), node('p', 'version-source', version.snapshot.archived ? 'Status: Archiviert' : 'Status: Aktiv'));
      details.append(snapshot);
      item.append(head, node('p', '', version.reason === 'created' ? 'Eintrag erstellt' : version.reason), details);
      return item;
    });
    $('detail-content').replaceChildren(badges, title, node('p', 'detail-body', memory.content), meta, actions, historyTitle, ...timeline);
  } catch (error) {
    if (serial !== detailRequest) return;
    const heading = node('h2', '', 'Eintrag nicht verfügbar'); heading.id = 'detail-title';
    $('detail-content').replaceChildren(heading, node('p', 'detail-body', error.message));
  }
}
let toastTimeout;
function toast(text) { clearTimeout(toastTimeout); $('toast').textContent = text; $('toast').hidden = false; toastTimeout = setTimeout(() => $('toast').hidden = true, 2600); }
$('detail-dialog').addEventListener('close', () => { ++detailRequest; state.selected = null; history.replaceState(null, '', location.pathname + location.search + (window.brainMap?.isOpen() ? '#map' : '')); });
$('close-detail').addEventListener('click', () => $('detail-dialog').close());
$('detail-dialog').addEventListener('click', event => { if (event.target === $('detail-dialog')) { const box = $('detail-dialog').getBoundingClientRect(); if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) $('detail-dialog').close(); } });
document.querySelectorAll('[data-view]').forEach(button => button.addEventListener('click', () => {
  window.brainMap?.hide();
  state.status = button.dataset.view; state.page = 1;
  document.querySelectorAll('[data-view]').forEach(item => { item.classList.toggle('selected', item === button); item.setAttribute('aria-pressed', String(item === button)); });
  $('breadcrumb').textContent = state.status === 'active' ? 'Wissen' : 'Archiv';
  $('page-title').textContent = state.status === 'active' ? 'Dein Brain. Im Überblick.' : 'Wissen mit Geschichte.';
  $('page-description').textContent = state.status === 'active' ? 'Was deine Agenten gelernt haben — an einem Ort.' : 'Frühere Einträge, ihre Quellen und jede Änderung.';
  $('library-title').textContent = state.status === 'active' ? 'Wissensbibliothek' : 'Archiv';
  load();
}));
let searchTimeout;
$('filters').addEventListener('submit', event => { event.preventDefault(); clearTimeout(searchTimeout); state.page = 1; load(); });
$('search').addEventListener('input', () => { clearTimeout(searchTimeout); searchTimeout = setTimeout(() => { state.page = 1; load(); }, 250); });
['kind','sort'].forEach(id => $(id).addEventListener('change', () => { state.page = 1; load(); }));
$('reset-filters').addEventListener('click', () => { $('search').value = ''; $('kind').value = ''; state.scope = ''; state.page = 1; load(); });
$('previous').addEventListener('click', () => { state.page--; load(); });
$('next').addEventListener('click', () => { state.page++; load(); });
$('refresh').addEventListener('click', () => { load(); window.brainMap?.refresh(); if (state.selected) openMemory(state.selected); });
$('memory-grid').replaceChildren(...Array.from({ length: 3 }, () => node('div', 'skeleton')));
load();
const match = location.hash.match(/^#memory=([0-9a-f-]{36})$/i); if (match) openMemory(match[1]);
setInterval(() => { if (!document.hidden && !state.busy && !document.activeElement.closest('input,select,dialog,.memory-card,.scope-button')) load({ quiet: true }); }, 15000);
