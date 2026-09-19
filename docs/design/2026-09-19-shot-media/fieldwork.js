(() => {
  'use strict';
  const icons = {
    arrow: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14m-6-6 6 6-6 6"/></svg>',
    back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 12H5m6 6-6-6 6-6"/></svg>',
    check: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4.5 4.5L19 7"/></svg>',
    plus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    close: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M6 18 18 6"/></svg>',
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m8 5 11 7-11 7Z"/></svg>',
    pause: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5h3v14H7zm7 0h3v14h-3z"/></svg>',
    prev: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 6-6 6 6 6"/></svg>',
    next: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>',
    undo: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 6 4 10l4 4M4 10h10a5 5 0 0 1 0 10"/></svg>',
    star: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3 2.8 5.7 6.3.9-4.5 4.4 1 6.3-5.6-3-5.6 3 1.1-6.3L3 9.6l6.2-.9Z"/></svg>',
    lock: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/></svg>',
    export: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15V3m-4 4 4-4 4 4M5 12v8h14v-8"/></svg>',
    down: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>',
    video: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="6" width="13" height="12" rx="2"/><path d="m16 10 5-3v10l-5-3"/></svg>'
  };
  const main = document.getElementById('main');
  const dialog = document.getElementById('dialog');
  const data = [
    {id:'after', name:'After hours.', subtitle:'One bucket. A few worth keeping.', date:'TODAY · 19 SEP', place:'At the range', image:'range', recordings:[{id:'after-1', name:'Recording 01', duration:'08:42', count:4},{id:'after-2',name:'Recording 02',duration:'06:18',count:3}]},
    {id:'nine',name:'Nine before nine.',subtitle:'Good company. Better light.',date:'SUN · 13 SEP',place:'Out on the course',image:'course',recordings:[{id:'nine-1',name:'Recording 01',duration:'04:26',count:3},{id:'nine-2',name:'Recording 02',duration:'02:14',count:2}]},
    {id:'short',name:'A little short game.',subtitle:'The quiet end of the range.',date:'FRI · 11 SEP',place:'At the range',image:'range',recordings:[{id:'short-1',name:'Recording 01',duration:'05:12',count:4}]}
  ];
  const moments = [];
  const draftFor = () => ({format:'9:16',trimStart:0,trimEnd:8.4,trace:false,favourite:false});
  function makeMoments(session) {
    let n = 0;
    session.recordings.forEach((recording, r) => {
      for (let i=0;i<recording.count;i++) {
        n++;
        moments.push({id:`${recording.id}-${i+1}`,session:session.id,recording:recording.id,number:n,sourceStart:38+i*53+r*29,status:'pending',draft:draftFor(),saved:null});
      }
    });
  }
  data.forEach(makeMoments);
  const seed = moments.find(m => m.session==='nine');
  seed.status='kept';seed.draft.favourite=true;seed.saved={...seed.draft};
  const state = {view:'review',session:'after',selected:'after-1-1',complete:false,history:[],filter:'all',playing:false,playhead:3.2,returnView:'review'};
  let toastTimer;
  let playbackTimer;
  const asset = session => `assets/${session.image}.png`;
  const getSession = () => data.find(s=>s.id===state.session);
  const getMoment = () => moments.find(m=>m.id===state.selected);
  const currentMoments = () => moments.filter(m=>m.session===state.session);
  const shots = () => moments.filter(m=>m.status==='kept');
  const number = n => String(n).padStart(2,'0');
  const time = n => `${number(Math.floor(n/60))}:${number(Math.floor(n%60))}`;
  const decimal = n => `${Number(n).toFixed(1)}s`;
  const countText = (n,singular,plural=`${singular}s`) => `${n} ${n===1?singular:plural}`;
  function fitSources() {
    document.querySelectorAll('.fitted-source').forEach(source=>{
      const img=source.querySelector('img'),canvas=source.closest('.export-canvas');
      if(!img.naturalWidth||!canvas.clientWidth)return;
      const ratio=img.naturalWidth/img.naturalHeight;
      if(canvas.dataset.format==='Original')canvas.style.aspectRatio=String(ratio);
      const width=Math.min(canvas.clientWidth,canvas.clientHeight*ratio);
      source.style.width=`${width}px`;
      source.style.height=`${width/ratio}px`;
      source.style.flex='0 0 auto';
    });
  }
  function notify(message) {
    const toast = document.getElementById('toast');toast.textContent=message;toast.classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.classList.remove('visible'),3300);
  }
  function stopPlayback() {
    clearInterval(playbackTimer);state.playing=false;
    document.querySelectorAll('[data-action="play"]').forEach(button=>{button.innerHTML=icons.play;button.setAttribute('aria-label','Play simulated clip preview');});
  }
  function syncNavigation() {
    document.querySelectorAll('[data-action="navigate"]').forEach(button=>{
      const active = button.dataset.view===((state.view==='review')?'sessions':(state.view==='studio'?state.returnView==='shots'?'shots':'sessions':state.view));
      if(active) button.setAttribute('aria-current','page'); else button.removeAttribute('aria-current');
    });
    document.querySelectorAll('.saved-count').forEach(el=>el.textContent=shots().length);
  }
  function sourceButtons() {
    const selected = getMoment();
    return `<div class="source-list">${getSession().recordings.map(recording=>`<button class="source-button" data-action="source" data-id="${recording.id}" aria-pressed="${selected?.recording===recording.id}"><img src="${asset(getSession())}" alt=""/><span><strong>${recording.name}</strong><small>${recording.duration} · ${recording.count} moments</small></span></button>`).join('')}</div>`;
  }
  function review() {
    const session=getSession(), moment=getMoment(), list=currentMoments(), index=list.indexOf(moment), kept=list.filter(m=>m.status==='kept').length, done=list.filter(m=>m.status!=='pending').length;
    return `<section class="review-layout view-fade" aria-label="Review session moments">
      <aside class="session-rail"><button class="back-label" data-action="navigate" data-view="sessions">${icons.back}All sessions</button><p class="eyebrow red">${session.date}</p><h1>${session.name}</h1><p class="session-note">${session.subtitle}</p><div class="rail-divider"></div><div class="recordings-label"><span class="eyebrow">Recordings</span><span class="eyebrow muted">${number(session.recordings.length)}</span></div>${sourceButtons()}<p class="rail-footer">${icons.lock}Your footage, on your device.<br>Originals stay untouched.</p></aside>
      <div class="review-stage"><div class="mobile-session-heading"><button class="back-label" data-action="navigate" data-view="sessions" aria-label="Back to sessions">${icons.back}</button><div><h1>${session.name}</h1><p class="heading-date">${session.date} · ${session.recordings.length} recordings</p></div><button class="recording-select" data-action="sources" aria-label="Switch source recording">${icons.video}${icons.down}</button></div>
      <div class="stage-caption"><p class="eyebrow muted">${state.complete?'SESSION REVIEWED':`${session.recordings.find(r=>r.id===moment.recording).name} · Possible shot`}</p><div class="frame-number">${number(index+1)} <span>/ ${number(list.length)}</span></div></div>
      ${state.complete?`<div class="completed-stage"><span class="complete-eye" aria-hidden="true">${icons.check}</span><div class="complete-symbol">${number(kept)}</div><div><h2>A good day.<br>Well kept.</h2><p>${countText(kept,'shot')} saved from this session. Time to make them yours.</p><button class="action" data-action="navigate" data-view="shots">See your shots ${icons.arrow}</button></div></div>`:`<div class="media-stage"><img src="${asset(session)}" alt="Fictional ${session.image==='range'?'golf driving range':'golf course'} sample used to explore shot review"/><span class="sample-flag">SAMPLE THUMBNAIL</span><span class="clip-corner"><span></span>${time(moment.sourceStart)}</span><span class="giant-number" aria-hidden="true">${number(moment.number)}</span><div class="frame-note"><strong>One to remember?</strong>8.4 seconds, all yours.</div><button class="play-control" data-action="play" aria-label="Play simulated clip preview">${icons.play}</button></div>
      <div class="stage-timeline"><div class="tick-strip"><span class="timeline-playhead" style="left:${state.playhead/8.4*100}%"></span></div><div class="time-labels"><span>${time(moment.sourceStart)}</span><span>SIMULATED TIMELINE</span><span>${time(moment.sourceStart+8.4)}</span></div></div>`}
      <div class="transport"><span class="transport-note">${state.complete?'Every original is still here.':'Possible moments. You choose the shots.'}</span><div class="transport-group"><button class="icon-button" data-action="previous" aria-label="Previous moment" ${index===0?'disabled':''}>${icons.prev}</button><button class="icon-button" data-action="next" aria-label="Next moment" ${index===list.length-1?'disabled':''}>${icons.next}</button></div></div></div>
      <aside class="review-decisions"><p class="eyebrow">The good stuff</p><h2>${state.complete?'That’s<br>a keeper.':'Less footage.<br>More feeling.'}</h2><p class="decision-copy">${state.complete?'Your best moments are ready for a trim, a trace, and their next life.':'Keep the ones you love. Skip the rest. Your original recordings stay right here.'}</p><div class="keep-status">${moment.status==='kept'?`${icons.check}Added to your shots`:moment.status==='skipped'?'Skipped · still in the original':'Ball flight not tracked'}</div><div class="decision-actions">${state.complete?`<button class="action light" data-action="review-again">Review again</button>`:`<button class="action light" data-action="skip">Skip ${icons.next}</button><button class="action primary keep-button" data-action="keep">${icons.plus}Keep shot</button>`}</div><div class="undo-line"><button class="text-button muted" data-action="undo" ${state.history.length?'':'disabled'}>${icons.undo}Undo last choice</button></div><div class="progress-section"><div class="progress-copy"><span>${kept} kept</span><span class="muted">${done} of ${list.length} reviewed</span></div><div class="progress-line">${list.map(m=>`<button data-action="select-moment" data-id="${m.id}" class="${m.id===moment.id?'current':''} ${m.status}" aria-label="Review moment ${m.number}, ${m.status}"><i></i></button>`).join('')}</div></div><button class="text-button editor-link" data-action="edit">${moment.status==='kept'?'Edit this shot':'Open in studio'}${icons.arrow}</button><div class="responsive-source"><p class="eyebrow muted" style="margin-bottom:8px">Recordings</p>${sourceButtons()}</div><p class="prototype-note">Sample session · detection and footage are illustrative.</p></aside>
    </section>`;
  }
  function sessionsPage() {
    return `<section class="collection-page view-fade"><div class="page-heading"><div><p class="eyebrow red">Get out. Get a few good ones.</p><h1>Your days.<br>Well kept.</h1><p class="subheading">Every session starts with a recording.<br>Every keeper starts with you.</p></div><button class="text-button" data-action="record">${icons.plus}New session</button></div><div class="sessions-list">${data.map((session,i)=>{const list=moments.filter(m=>m.session===session.id),kept=list.filter(m=>m.status==='kept').length,pending=list.filter(m=>m.status==='pending').length;return `<article class="session-row"><span class="session-index" aria-hidden="true">${number(data.length-i)}</span><div class="session-info"><p class="eyebrow">${session.date}</p><h2>${session.name}</h2><p>${countText(session.recordings.length,'recording')} · ${countText(list.length,'moment')}</p></div><button class="session-picture" data-action="open-session" data-id="${session.id}" aria-label="Review ${session.name}"><img src="${asset(session)}" alt="Sample ${session.image==='range'?'driving range':'course'} scenery"/><span class="tag">${pending?`${pending} moments to review`:`${kept} shots kept`}</span></button><button class="session-open" data-action="open-session" data-id="${session.id}" aria-label="Open ${session.name}"><span class="circle-arrow">${icons.arrow}</span><span class="session-state">${kept?`${countText(kept,'shot')} already kept`:'A fresh batch of possibilities'}</span></button></article>`}).join('')}</div><p class="sample-footnote">Fictional sample sessions. Original recordings stay on your device.</p></section>`;
  }
  function shotsPage() {
    const all=shots(), filtered=state.filter==='keepers'?all.filter(m=>(m.saved||m.draft).favourite):all;
    return `<section class="collection-page view-fade"><div class="page-heading"><div><p class="eyebrow red">The ones worth another look.</p><h1>Good shots.<br>Yours to keep.</h1><p class="subheading">A collection of moments, ready for their next life.</p></div><button class="text-button" data-action="navigate" data-view="sessions">Find more ${icons.arrow}</button></div><div class="filters" aria-label="Shot filters"><button class="filter-button" data-action="filter" data-filter="all" aria-pressed="${state.filter==='all'}">All shots <span>${all.length}</span></button><button class="filter-button" data-action="filter" data-filter="keepers" aria-pressed="${state.filter==='keepers'}">${icons.star}Keepers <span>${all.filter(m=>(m.saved||m.draft).favourite).length}</span></button></div>${filtered.length?`<div class="shot-list">${filtered.map(moment=>{const session=data.find(s=>s.id===moment.session),edit=moment.saved||moment.draft;return `<article class="shot-tile"><button class="shot-open" data-action="open-shot" data-id="${moment.id}"><div class="shot-photo"><img src="${asset(session)}" alt="Sample shot ${number(moment.number)} from ${session.name}"/><span class="shot-numeral">${number(moment.number)}</span>${edit.trace?'<span class="tag">Manual trace</span>':''}${edit.favourite?`<span class="starred" aria-label="Keeper">${icons.star}</span>`:''}</div><div class="shot-meta"><h2>Shot ${number(moment.number)}</h2><span>${decimal(edit.trimEnd-edit.trimStart)}</span></div><p>${session.name} · ${session.date.replace(' · ', ' / ')}</p></button></article>`}).join('')}</div>`:`<div class="empty-shots"><h2>${state.filter==='keepers'?'Your favourites<br>live here.':'Make room for<br>the good ones.'}</h2><p>${state.filter==='keepers'?'Open a saved shot and mark it as a Keeper.':'Review a session and keep a moment. Your selected shots will appear here.'}</p><button class="action primary" data-action="navigate" data-view="${state.filter==='keepers'?'shots':'sessions'}" ${state.filter==='keepers'?'data-reset-filter="true"':''}>${state.filter==='keepers'?'See all shots':'Review a session'}${icons.arrow}</button></div>`}<p class="sample-footnote">${all.length?`${countText(all.length,'shot')} saved in this prototype. `:''}Selections reset when you reload.</p></section>`;
  }
  function sourceMarkup(moment, format, trace) {
    const session=data.find(s=>s.id===moment.session);
    return `<div class="export-canvas" data-format="${format}"><div class="fitted-source"><img src="${asset(session)}" alt="Complete sample source frame, fitted without cropping"/>${trace?`<svg class="trace-overlay" viewBox="0 0 600 400" preserveAspectRatio="none" aria-hidden="true"><path d="M266 331 C277 285 319 158 383 90 C409 62 430 58 453 73"/></svg>`:''}</div><div class="trace-label"><span>${trace?'Manual trace · illustration':'Ball flight not tracked'}</span><span class="sample">SAMPLE</span></div></div>`;
  }
  function studioPage() {
    const moment=getMoment(),session=data.find(s=>s.id===moment.session),draft=moment.draft,changed=moment.status!=='kept'||JSON.stringify(draft)!==JSON.stringify(moment.saved);
    return `<section class="studio-page view-fade"><div class="studio-heading"><button class="back-label" data-action="studio-back">${icons.back}${state.returnView==='shots'?'Shots':'Review'}</button><div class="studio-title"><h1>Shot ${number(moment.number)} / ${session.name}</h1><p>From ${session.recordings.find(r=>r.id===moment.recording).name.toLowerCase()} · source preserved</p></div><button class="action primary" data-action="export">Export ${icons.export}</button></div><div class="studio-layout"><div class="studio-media-area"><div class="studio-media-top"><span>SHOT STUDIO</span><span>SAMPLE STILL · FITTED SOURCE</span></div><div id="canvas-holder">${sourceMarkup(moment,draft.format,draft.trace)}</div><div class="studio-controls"><span class="spacer"></span><button class="icon-button" data-action="frame-back" aria-label="Step simulated timeline back">${icons.prev}</button><button class="icon-button play-studio" data-action="play" aria-label="Play simulated clip preview">${icons.play}</button><button class="icon-button" data-action="frame-next" aria-label="Step simulated timeline forward">${icons.next}</button><span class="studio-clock"><span id="playhead-label">${state.playhead.toFixed(1)}</span> / 8.4s</span></div></div><aside class="editor-panel"><h2>Make it yours.</h2><p class="muted">A quick cut. A little character.</p><div class="edit-columns"><div class="editor-section"><div class="section-topline"><span>Format</span><span class="value">Fit full frame</span></div><div class="format-options">${['9:16','1:1','Original'].map(format=>`<button class="format-button" data-action="format" data-format="${format}" aria-pressed="${draft.format===format}"><span class="format-icon" aria-hidden="true"></span>${format}</button>`).join('')}</div><p class="fit-note">The whole source stays visible in every format.</p></div><div class="editor-section"><div class="section-topline"><span>Trim</span><span class="value" id="trim-duration">${decimal(draft.trimEnd-draft.trimStart)} selected</span></div><div class="filmstrip" aria-hidden="true">${Array.from({length:5},()=>`<img src="${asset(session)}" alt=""/>`).join('')}</div><div class="trim-inputs"><label>In <output for="trim-start" id="trim-start-value">${decimal(draft.trimStart)}</output><input id="trim-start" data-trim="trimStart" type="range" min="0" max="8.3" step="0.1" value="${draft.trimStart}" aria-label="Trim start in seconds"/></label><label>Out <output for="trim-end" id="trim-end-value">${decimal(draft.trimEnd)}</output><input id="trim-end" data-trim="trimEnd" type="range" min="0.1" max="8.4" step="0.1" value="${draft.trimEnd}" aria-label="Trim end in seconds"/></label></div></div><div class="editor-section"><div class="trace-row"><div><strong>Manual trace</strong><p>An illustrative annotation.<br>Not an observed ball path.</p></div><button class="toggle" role="switch" aria-checked="${draft.trace}" aria-label="Manual trace" data-action="trace"></button></div></div><div class="editor-section" style="padding-bottom:0"><button class="keep-favourite" data-action="favourite" aria-pressed="${draft.favourite}"><span class="favourite-icon">${icons.star}</span>${draft.favourite?'A Keeper. One of your favourites.':'Mark this one as a Keeper'}</button></div></div><div class="editor-save"><button class="action light" data-action="discard">Reset edits</button><button class="action dark" data-action="save">${moment.status==='kept'?'Save edits':'Keep shot'}</button></div><p class="draft-note" id="draft-note">${changed?'Draft changes. Your original stays untouched.':'Edits saved in this prototype.'}</p></aside></div></section>`;
  }
  function render({focus=false}={}) {
    stopPlayback();
    main.innerHTML=state.view==='sessions'?sessionsPage():state.view==='shots'?shotsPage():state.view==='studio'?studioPage():review();
    syncNavigation();
    requestAnimationFrame(fitSources);
    if(focus) {main.focus({preventScroll:true});window.scrollTo({top:0,behavior:'instant'});}
  }
  function navigate(view) {
    if(view==='studio') {if(state.view!=='studio')state.returnView=state.view==='shots'?'shots':'review';state.view='studio';}
    else {state.view=view;if(view==='shots')state.filter='all';}
    render({focus:true});
  }
  function selectMoment(id) {state.selected=id;state.session=getMoment().session;state.complete=false;state.playhead=3.2;render();}
  function openSession(id) {state.session=id;state.selected=(currentMoments().find(m=>m.status==='pending')||currentMoments()[0]).id;state.complete=false;state.view='review';state.playhead=3.2;render({focus:true});}
  function choose(status) {
    const moment=getMoment();
    state.history.push({id:moment.id,status:moment.status,saved:moment.saved?{...moment.saved}:null,draft:{...moment.draft}});
    moment.status=status;moment.saved=status==='kept'?{...moment.draft}:null;
    const list=currentMoments(),index=list.indexOf(moment),next=list.slice(index+1).find(m=>m.status==='pending')||list.slice(0,index).find(m=>m.status==='pending');
    if(next) {state.selected=next.id;state.playhead=3.2;} else state.complete=true;
    render();notify(status==='kept'?`Shot ${number(moment.number)} kept. Ready to make yours.`:`Moment ${number(moment.number)} skipped. Original footage stays intact.`);
  }
  function undo() {
    const last=state.history.pop();if(!last)return;const moment=moments.find(m=>m.id===last.id);Object.assign(moment,{status:last.status,saved:last.saved,draft:last.draft});state.selected=moment.id;state.session=moment.session;state.complete=false;state.view='review';render();notify(`Last choice undone. Back to moment ${number(moment.number)}.`);
  }
  function modal(inner) {stopPlayback();dialog.innerHTML=inner;if(!dialog.open)dialog.showModal();requestAnimationFrame(fitSources);}
  function modalTop(eyebrow) {return `<div class="dialog-top"><p class="eyebrow red">${eyebrow}</p><button class="icon-button" data-action="close-dialog" aria-label="Close dialog">${icons.close}</button></div>`;}
  function recordModal() {modal(`${modalTop('Make a day of it')}<h2 id="dialog-title" class="dialog-title">Let it roll.</h2><p class="dialog-copy">Set your phone down. Play your game. Come back to the moments worth keeping.</p><div class="dialog-actions"><button class="action primary" data-action="add-sample" data-kind="record"><span class="record-dot" style="background:currentColor;box-shadow:none"></span>Try a sample recording</button><button class="action light" data-action="add-sample" data-kind="import">${icons.plus}Import sample footage</button></div><p class="dialog-note">Design prototype only. These actions add a fictional session. They do not access your camera, microphone or files.</p>`);}
  function sourcesModal() {modal(`${modalTop('Session recordings')}<h2 id="dialog-title" class="dialog-title">Take your pick.</h2><p class="dialog-copy">${getSession().name} Each recording contains its own possible moments.</p>${sourceButtons()}<p class="dialog-note">All moments are illustrative sample detections.</p>`);}
  function exportModal() {
    const moment=getMoment(),draft=moment.draft;
    modal(`${modalTop('One for the collection')}<h2 id="dialog-title" class="dialog-title">Ready for<br>its next life.</h2><div class="export-preview">${sourceMarkup(moment,draft.format,draft.trace)}</div><div class="export-detail"><span>Canvas</span><strong>${draft.format} · fitted source</strong></div><div class="export-detail"><span>Selected clip</span><strong>${decimal(draft.trimStart)} → ${decimal(draft.trimEnd)}</strong></div><div class="export-detail"><span>Trace</span><strong>${draft.trace?'Manual annotation':'Off · ball flight not tracked'}</strong></div><p class="dialog-note">This is an export preview. No video is encoded, downloaded or posted by this prototype. A finished export would preserve the Manual trace label.</p><div class="dialog-actions" style="margin-top:18px"><button class="action primary" data-action="close-dialog">Back to the studio ${icons.arrow}</button></div>`);
  }
  function refreshStudio() {
    const m=getMoment();document.getElementById('canvas-holder').innerHTML=sourceMarkup(m,m.draft.format,m.draft.trace);
    document.getElementById('draft-note').textContent='Draft changes. Your original stays untouched.';
    requestAnimationFrame(fitSources);
  }
  function play() {
    state.playing=!state.playing;
    document.querySelectorAll('[data-action="play"]').forEach(el=>{el.innerHTML=state.playing?icons.pause:icons.play;el.setAttribute('aria-label',state.playing?'Pause simulated clip preview':'Play simulated clip preview');});
    clearInterval(playbackTimer);
    if(state.playing) {
      if(state.playhead>=8.4)state.playhead=0;
      playbackTimer=setInterval(()=>{state.playhead=Math.min(8.4,state.playhead+.1);updatePlayhead();if(state.playhead>=8.4)play();},100);
    }
  }
  function updatePlayhead() {const playhead=document.querySelector('.timeline-playhead');if(playhead)playhead.style.left=`${state.playhead/8.4*100}%`;const label=document.getElementById('playhead-label');if(label)label.textContent=state.playhead.toFixed(1);}
  document.addEventListener('click', event => {
    const button=event.target.closest('button[data-action]');if(!button||button.disabled)return;
    const action=button.dataset.action;
    if(action==='navigate')navigate(button.dataset.view);
    else if(action==='open-session')openSession(button.dataset.id);
    else if(action==='keep'||action==='skip')choose(action==='keep'?'kept':'skipped');
    else if(action==='undo')undo();
    else if(action==='next'||action==='previous'){const list=currentMoments(),i=list.indexOf(getMoment()),m=list[i+(action==='next'?1:-1)];if(m)selectMoment(m.id);}
    else if(action==='select-moment')selectMoment(button.dataset.id);
    else if(action==='source'){const list=currentMoments().filter(m=>m.recording===button.dataset.id);if(dialog.open)dialog.close();state.complete=false;selectMoment((list.find(m=>m.status==='pending')||list[0]).id);}
    else if(action==='sources')sourcesModal();
    else if(action==='review-again'){state.complete=false;state.selected=currentMoments()[0].id;render();}
    else if(action==='edit'){state.returnView='review';navigate('studio');}
    else if(action==='open-shot'){state.selected=button.dataset.id;state.session=getMoment().session;state.returnView='shots';state.view='studio';state.playhead=3.2;render({focus:true});}
    else if(action==='studio-back'){state.view=state.returnView;render({focus:true});}
    else if(action==='filter'){state.filter=button.dataset.filter;render();}
    else if(action==='record')recordModal();
    else if(action==='close-dialog')dialog.close();
    else if(action==='add-sample'){
      const n=data.length+1,id=`sample-${n}`,session={id,name:'A fresh start.',subtitle:'A new session. New possibilities.',date:'TODAY · SAMPLE',place:'At the range',image:'range',recordings:[{id:`${id}-1`,name:'Recording 01',duration:'03:26',count:3}]};data.unshift(session);makeMoments(session);dialog.close();openSession(id);notify(`Sample ${button.dataset.kind==='import'?'footage imported':'recording added'}. 3 possible moments to review.`);
    }
    else if(action==='format'){getMoment().draft.format=button.dataset.format;document.querySelectorAll('.format-button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.format===getMoment().draft.format)));refreshStudio();}
    else if(action==='trace'){const m=getMoment();m.draft.trace=!m.draft.trace;button.setAttribute('aria-checked',String(m.draft.trace));refreshStudio();}
    else if(action==='favourite'){const m=getMoment();m.draft.favourite=!m.draft.favourite;button.setAttribute('aria-pressed',String(m.draft.favourite));button.innerHTML=`<span class="favourite-icon">${icons.star}</span>${m.draft.favourite?'A Keeper. One of your favourites.':'Mark this one as a Keeper'}`;document.getElementById('draft-note').textContent='Draft changes. Your original stays untouched.';}
    else if(action==='save'){const m=getMoment();m.status='kept';m.saved={...m.draft};render();notify('Shot and edits saved in this prototype.');}
    else if(action==='discard'){const m=getMoment();m.draft=m.saved?{...m.saved}:draftFor();render();notify(m.saved?'Draft reset to your last saved edits.':'Draft reset. Your original is unchanged.');}
    else if(action==='export')exportModal();
    else if(action==='play')play();
    else if(action==='frame-back'||action==='frame-next'){stopPlayback();state.playhead=Math.max(0,Math.min(8.4,state.playhead+(action==='frame-next'?.1:-.1)));document.querySelectorAll('[data-action="play"]').forEach(b=>{b.innerHTML=icons.play;b.setAttribute('aria-label','Play simulated clip preview');});updatePlayhead();}
  });
  document.addEventListener('input',event=>{
    const input=event.target;if(!input.matches('input[data-trim]'))return;const draft=getMoment().draft;
    if(input.dataset.trim==='trimStart')draft.trimStart=Math.min(Number(input.value),Math.round((draft.trimEnd-.1)*10)/10);else draft.trimEnd=Math.max(Number(input.value),Math.round((draft.trimStart+.1)*10)/10);
    input.value=draft[input.dataset.trim];
    document.getElementById('trim-start-value').textContent=decimal(draft.trimStart);document.getElementById('trim-end-value').textContent=decimal(draft.trimEnd);document.getElementById('trim-duration').textContent=`${decimal(draft.trimEnd-draft.trimStart)} selected`;document.getElementById('draft-note').textContent='Draft changes. Your original stays untouched.';
  });
  window.addEventListener('message',event=>{if(event.origin!==window.location.origin||event.source!==window.parent)return;if(event.data?.type==='ronde:navigate'&&['sessions','shots','studio'].includes(event.data.view))navigate(event.data.view);});
  document.addEventListener('keydown',event=>{
    if(dialog.open||event.target.matches('input,select,textarea')||state.view!=='review')return;
    if(event.key==='ArrowRight'||event.key==='ArrowLeft'){event.preventDefault();const list=currentMoments(),next=list[list.indexOf(getMoment())+(event.key==='ArrowRight'?1:-1)];if(next)selectMoment(next.id);}
  });
  dialog.addEventListener('click',event=>{if(event.target===dialog){const bounds=dialog.getBoundingClientRect();if(event.clientX<bounds.left||event.clientX>bounds.right||event.clientY<bounds.top||event.clientY>bounds.bottom)dialog.close();}});
  document.addEventListener('load',event=>{
    const img=event.target;
    if(!(img instanceof HTMLImageElement)||!img.closest('.fitted-source')||!img.naturalWidth)return;
    fitSources();
  },true);
  window.addEventListener('resize',fitSources);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)stopPlayback();});
  render();
})();
