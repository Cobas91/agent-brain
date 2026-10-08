'use strict';
(() => {
  const map = { enabled:false, graph:null, prediction:null, args:null, selected:null, serial:0, querySerial:0, zoom:[0,0,1000,600] };
  const svg = $('knowledge-map');
  const score = value => Number(value).toLocaleString('de-DE', {minimumFractionDigits:2,maximumFractionDigits:3});
  const svgnode = (tag, attrs = {}, text) => {
    const item = document.createElementNS('http://www.w3.org/2000/svg',tag);
    for (const [key,value] of Object.entries(attrs)) item.setAttribute(key,String(value));
    if (text !== undefined) item.textContent = text;
    return item;
  };
  function error(message) { $('map-error').textContent = message; $('map-error').hidden = !message; }
  function populateScopes(data) {
    for (const [id, question] of [['map-scope',false],['question-project',true]]) {
      const select = $(id), old = select.value;
      const items = question ? [['','Globales Wissen']] : [['','Alle Bereiche'],['global','Global']];
      for (const entry of data.scopes.filter(x => x.scope !== 'global')) items.push([question ? entry.scope.replace(/^project:/,'') : entry.scope, scopeLabel(entry.scope) + (question ? ' + global' : '')]);
      select.replaceChildren(...items.map(([value,label]) => { const option = node('option','',label); option.value = value; return option; }));
      if (items.some(([value]) => value === old)) select.value = old;
    }
  }
  function layout(nodes, edges) {
    const positions = new Map(nodes.map((item,i) => [item.id,{...item,x:500 + Math.cos(i*2.399963)*Math.sqrt(i+1)*38,y:300 + Math.sin(i*2.399963)*Math.sqrt(i+1)*38,dx:0,dy:0}]));
    const list = [...positions.values()];
    // Deterministic force layout. Edges carry actual cosine scores, positions are only orientation.
    for (let step=0;step<150;step++) {
      for (const point of list) { point.dx=(500-point.x)*.008; point.dy=(300-point.y)*.008; }
      for (let i=0;i<list.length;i++) for (let j=i+1;j<list.length;j++) {
        const a=list[i], b=list[j], dx=a.x-b.x, dy=a.y-b.y, distance=Math.sqrt(dx*dx+dy*dy)+.1, force=2600/(distance*distance+40);
        a.dx+=dx/distance*force; a.dy+=dy/distance*force; b.dx-=dx/distance*force; b.dy-=dy/distance*force;
      }
      for (const edge of edges) {
        const a=positions.get(edge.source), b=positions.get(edge.target); if (!a || !b) continue;
        const dx=b.x-a.x,dy=b.y-a.y,distance=Math.sqrt(dx*dx+dy*dy)+.1, desired=80+(1-edge.similarity)*160, force=(distance-desired)*.035;
        a.dx+=dx/distance*force; a.dy+=dy/distance*force; b.dx-=dx/distance*force; b.dy-=dy/distance*force;
      }
      for (const point of list) { point.x=Math.max(100,Math.min(900,point.x+Math.max(-8,Math.min(8,point.dx)))); point.y=Math.max(90,Math.min(510,point.y+Math.max(-8,Math.min(8,point.dy)))); }
    }
    return positions;
  }
  function setView() { svg.setAttribute('viewBox',map.zoom.join(' ')); }
  function fit() {
    if(!map.positions?.size)return;
    const list=[...map.positions.values()],xs=list.map(x=>x.x),ys=list.map(x=>x.y);
    const w=Math.max(600,Math.max(...xs)-Math.min(...xs)+340,(Math.max(...ys)-Math.min(...ys)+180)/.6),h=w*.6;
    map.zoom=[(Math.min(...xs)+Math.max(...xs))/2-w/2,(Math.min(...ys)+Math.max(...ys))/2-h/2,w,h];setView();
  }
  function zoom(factor) {
    const [x,y,w,h] = map.zoom, newW=Math.max(250,Math.min(2200,w*factor)), newH=newW*.6;
    map.zoom=[x+(w-newW)/2,y+(h-newH)/2,newW,newH]; setView();
  }
  function draw() {
    if (!map.graph) return;
    const graph = map.graph, hits = new Map((map.prediction?.results || []).map((entry,i) => [entry.id,i+1]));
    const nodes = [...graph.nodes], edges = [...graph.edges];
    if (map.prediction) {
      nodes.push({id:'question',title:'Deine Frage',scope:'question',kind:'question'});
      for (const result of map.prediction.results) edges.push({source:'question',target:result.id,similarity:result.similarity,question:true});
    }
    const positions = layout(nodes,edges);
    map.positions=positions;svg.classList.toggle('dense-map',nodes.length>20);
    const defs=svgnode('defs'), pattern=svgnode('pattern',{id:'map-dots',width:24,height:24,patternUnits:'userSpaceOnUse'});
    pattern.append(svgnode('circle',{cx:1,cy:1,r:1,fill:'#2a392e'})); defs.append(pattern);
    svg.replaceChildren(defs,svgnode('rect',{x:-2000,y:-2000,width:6000,height:6000,fill:'url(#map-dots)'}));
    const edgeLayer=svgnode('g'), nodeLayer=svgnode('g'); svg.append(edgeLayer,nodeLayer);
    for (const edge of edges) {
      const a=positions.get(edge.source),b=positions.get(edge.target); if (!a || !b) continue;
      const selected=map.selected && [a.id,b.id].includes(map.selected);
      const line=svgnode('line',{x1:a.x,y1:a.y,x2:b.x,y2:b.y,class:edge.question ? 'question-edge' : 'map-edge'+(selected ? ' emphasized' : '')});
      line.append(svgnode('title',{},`${a.title} ↔ ${b.title}: ${score(edge.similarity)}`)); edgeLayer.append(line);
      if (edge.question || selected || graph.nodes.length <= 8) edgeLayer.append(svgnode('text',{x:(a.x+b.x)/2,y:(a.y+b.y)/2-8,'text-anchor':'middle',class:'edge-score'+(edge.question ? ' question-score' : '')},score(edge.similarity)));
    }
    for (const point of positions.values()) {
      const rank=hits.get(point.id), question=point.id==='question';
      const group=svgnode('g',{class:'map-node'+(rank ? ' hit' : '')+(question ? ' question' : '')+(map.selected===point.id ? ' selected' : '')+(map.prediction && !rank && !question ? ' dimmed' : ''),transform:`translate(${point.x},${point.y})`,tabindex:0,role:'button','aria-label':question ? 'Deine Frage: '+map.prediction.query : point.title+(rank ? `, Treffer ${rank}` : '')});
      group.append(svgnode('title',{},question ? map.prediction.query : point.title+' · '+scopeLabel(point.scope)),svgnode('circle',{r:rank || question ? 25 : 19,class:'node-ring'}));
      if (rank || question) group.append(svgnode('text',{'text-anchor':'middle',y:5,class:'rank-label'},question ? '?' : rank));
      else group.append(svgnode('circle',{r:4,class:'node-core'}));
      const label=svgnode('text',{'text-anchor':'middle',y:question ? -42 : 46,class:'node-label'});
      const words=point.title.split(/\s+/),lines=[''];
      for(const word of words){if(lines[lines.length-1].length+word.length>18 && lines[lines.length-1])lines.push('');lines[lines.length-1]+=(lines[lines.length-1] ? ' ' : '')+word;}
      lines.slice(0,2).forEach((line,index)=>label.append(svgnode('tspan',{x:0,dy:index ? 22 : 0},line.slice(0,20)+(index===1&&lines.length>2 ? '…' : ''))));group.append(label);
      const choose=()=>question ? $('retrieval-results').scrollIntoView({block:'nearest'}) : selectNode(point.id);
      group.addEventListener('click',choose); group.addEventListener('keydown',event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();choose();}});
      nodeLayer.append(group);
    }
    $('map-empty').hidden = graph.nodes.length !== 0;
    $('map-count').textContent=`${graph.nodes.length}${graph.truncated ? ' von '+graph.total : ''} Einträge · ${graph.edges.length} ${graph.edges.length===1 ? 'Verbindung' : 'Verbindungen'}`;
    if (graph.truncated) $('map-count').textContent+=' · neueste Einträge + Frage-Treffer';
    setView();
  }
  function resetInspector() {
    map.selected=null;
    $('node-inspector').replaceChildren(node('h3','','Eintrag auswählen'),node('p','','Klicke auf einen Punkt, um seine Verbindungen und den Inhalt zu sehen.'));
  }
  function selectNode(id) {
    const current=map.graph?.nodes.find(entry=>entry.id===id); if(!current) return;
    map.selected=id;
    const info=node('p','',`${scopeLabel(current.scope)} · ${kinds[current.kind] || current.kind} · v${current.revision}`);
    const open=node('button','secondary-button','Vollständigen Eintrag öffnen'); open.addEventListener('click',()=>openMemory(id));
    const linked=map.graph.edges.filter(edge=>edge.source===id || edge.target===id).sort((a,b)=>b.similarity-a.similarity);
    const related=linked.map(edge=>{
      const target=map.graph.nodes.find(entry=>entry.id===(edge.source===id ? edge.target : edge.source));
      const button=node('button','map-related'); button.append(node('span','',target.title),node('span','',score(edge.similarity))); button.addEventListener('click',()=>selectNode(target.id)); return button;
    });
    $('node-inspector').replaceChildren(node('h3','',current.title),info,open,node('h4','','ÄHNLICHE EINTRÄGE'),...(related.length ? related : [node('p','','Keine Verbindung bei dieser Linienschwelle. Senke den Wert, um schwächere Ähnlichkeiten zu sehen.') ]));
    draw();
  }
  let graphController, queryController;
  async function loadMap() {
    const serial=++map.serial; graphController?.abort(); graphController=new AbortController();
    $('map-section').setAttribute('aria-busy','true');
    const params=new URLSearchParams({scope:$('map-scope').value,threshold:$('edge-threshold').value,focus_ids:(map.prediction?.results || []).map(x=>x.id).join(',')});
    try {
      const graph=await api('/api/map?'+params,{signal:graphController.signal}); if(serial!==map.serial) return;
      map.graph=graph; error(''); draw();fit();
      if(map.selected && graph.nodes.some(entry=>entry.id===map.selected)) selectNode(map.selected); else resetInspector();
    } catch(failure) {if(serial===map.serial && failure.name!=='AbortError') error(failure.message);}
    finally {if(serial===map.serial) $('map-section').setAttribute('aria-busy','false');}
  }
  function clearQuestion() {
    ++map.querySerial; queryController?.abort(); map.prediction=null;map.args=null;
    $('retrieval-results').hidden=true;$('retrieval-results').replaceChildren();$('clear-question').hidden=true;$('ask-question').disabled=false;$('ask-question').textContent='Kontext anzeigen ↗';
  }
  function resultsPanel() {
    const result=map.prediction, container=$('retrieval-results'); container.hidden=false;
    const head=node('div','retrieval-heading'); head.append(node('strong','',`${result.results.length} ${result.results.length===1 ? 'Eintrag' : 'Einträge'} im Frage-Kontext`),node('p','',`${result.used_chars.toLocaleString('de-DE')} / ${result.max_chars.toLocaleString('de-DE')} Zeichen · Ähnlichkeit ab ${score(result.min_similarity)}`),node('p','context-snapshot','Suche '+time(result.searched_at)+' · '+(result.project ? result.project+' + global' : 'nur global')));
    const entries=result.results.map((entry,i)=>{
      const row=node('div','retrieval-row'), button=node('button');button.append(node('span','hit-number',String(i+1).padStart(2,'0')),node('span','',entry.title));button.addEventListener('click',()=>selectNode(entry.id));
      const details=node('details');details.append(node('summary','','Kontexttext ansehen'),node('p','context-content',entry.content),node('p','context-source','Quelle: '+entry.source));
      row.append(button,node('div','score','Frage-Ähnlichkeit '+score(entry.similarity)),details); return row;
    });
    container.replaceChildren(head,...entries);
    if(!entries.length) container.append(node('p','','Keine Treffer innerhalb der gewählten Suchgrenzen. Formuliere die Frage anders oder passe die Suchparameter an.'));
    $('clear-question').hidden=false;
  }
  async function runQuery(args) {
    clearQuestion(); const serial=++map.querySerial; queryController=new AbortController();map.args=args;
    $('ask-question').disabled=true;$('ask-question').textContent='Kontext wird gesucht …';error('');draw();
    try {
      const prediction=await api('/api/query',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(args),signal:queryController.signal});
      if(serial!==map.querySerial) return;
      map.prediction=prediction; $('map-scope').value=args.project ? 'project:'+args.project : 'global';
      state.scope=$('map-scope').value;
      if(state.overview) updateOverview(state.overview);
      resultsPanel();await loadMap();
    } catch(failure) {if(serial===map.querySerial && failure.name!=='AbortError') error(failure.message);}
    finally {if(serial===map.querySerial){$('ask-question').disabled=false;$('ask-question').textContent='Kontext anzeigen ↗';}}
  }
  function show() {
    map.enabled=true;document.querySelector('.library').hidden=true;$('map-section').hidden=false;
    document.querySelectorAll('[data-view]').forEach(button=>{button.classList.remove('selected');button.setAttribute('aria-pressed','false');});
    $('map-nav').classList.add('selected');$('map-nav').setAttribute('aria-pressed','true');
    $('breadcrumb').textContent='Wissenskarte';$('page-title').textContent='Dein Wissen. Verbunden.';$('page-description').textContent='Erkunde Zusammenhänge und den Kontext hinter einer Frage.';
    if(state.overview) populateScopes(state.overview);
    if(!map.graph || $('map-scope').value!==state.scope) { clearQuestion();$('map-scope').value=state.scope;$('question-project').value=state.scope.replace(/^project:/,'')==='global' ? '' : state.scope.replace(/^project:/,'');loadMap(); }
    history.replaceState(null,'','#map');
  }
  function hide() {
    if($('ask-question').disabled) clearQuestion();
    map.enabled=false;document.querySelector('.library').hidden=false;$('map-section').hidden=true;$('map-nav').classList.remove('selected');$('map-nav').setAttribute('aria-pressed','false');
    if(location.hash==='#map')history.replaceState(null,'',location.pathname+location.search);
  }
  function scopeChanged(scope) {
    if(!map.enabled) return;
    clearQuestion();$('map-scope').value=scope;$('question-project').value=scope==='global' ? '' : scope.replace(/^project:/,'');loadMap();
  }
  window.brainMap={updateOverview:populateScopes,hide,scopeChanged,isOpen:()=>map.enabled,refresh:()=>{if(map.enabled){if(map.args)runQuery(map.args);else loadMap();}}};
  $('map-nav').addEventListener('click',show);
  $('map-scope').addEventListener('change',()=>{state.scope=$('map-scope').value;if(state.overview)updateOverview(state.overview);scopeChanged(state.scope);});
  $('question-form').addEventListener('submit',event=>{
    event.preventDefault();runQuery({query:$('question').value.trim(),project:$('question-project').value || null,limit:Number($('query-limit').value),min_similarity:Number($('query-threshold').value),max_chars:Number($('query-budget').value)});
  });
  $('edge-threshold').addEventListener('input',()=>$('edge-value').textContent=score($('edge-threshold').value));
  $('edge-threshold').addEventListener('change',loadMap);
  $('clear-question').addEventListener('click',()=>{clearQuestion();$('question').value='';loadMap();});
  for(const id of ['query-limit','query-threshold','query-budget']) $(id).addEventListener('input',()=>{$('map-section').querySelector('.query-options summary span').textContent=`${$('query-limit').value} Treffer · Ähnlichkeit ab ${score($('query-threshold').value)} · ${$('query-budget').value} Zeichen`;});
  $('zoom-in').addEventListener('click',()=>zoom(.8));$('zoom-out').addEventListener('click',()=>zoom(1.25));$('fit-map').addEventListener('click',fit);
  svg.addEventListener('wheel',event=>{event.preventDefault();zoom(event.deltaY<0 ? .9 : 1.1);},{passive:false});
  let drag;
  svg.addEventListener('pointerdown',event=>{if(event.target.closest('.map-node'))return;drag={x:event.clientX,y:event.clientY,view:[...map.zoom]};svg.setPointerCapture(event.pointerId);svg.classList.add('panning');});
  svg.addEventListener('pointermove',event=>{if(!drag)return;const bounds=svg.getBoundingClientRect(),ratio=Math.max(drag.view[2]/bounds.width,drag.view[3]/bounds.height);map.zoom=[drag.view[0]-(event.clientX-drag.x)*ratio,drag.view[1]-(event.clientY-drag.y)*ratio,drag.view[2],drag.view[3]];setView();});
  const stopDrag=()=>{drag=null;svg.classList.remove('panning');};svg.addEventListener('pointerup',stopDrag);svg.addEventListener('pointercancel',stopDrag);
  if(location.hash==='#map')show();
})();
