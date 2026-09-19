'use strict';

// In-memory interaction study. A cut references the source; this demo does not encode video.
const recordingLibrary = {};
const recordingUI = {source: 1, tab: 'bookmarks', playing: false, serial: 20, undo: null};
function recordingCollection() {
  const key = state.session;
  if (!recordingLibrary[key]) {
    recordingLibrary[key] = [1200, 600].map((duration, i) => ({
      id: i + 1, duration, time: i ? 192 : 484,
      asset: key === 'coast' ? 'assets/course.png' : 'assets/range.png',
      bookmarks: (i ? [192] : [148, 484, 917]).map((time, j) => ({
        id: `${key}-${i + 1}-${j}`, time, before: 5, after: 5, cutId: null
      })), selected: `${key}-${i + 1}-${i ? 0 : 1}`
    }));
  }
  return recordingLibrary[key];
}
const currentRecording = () => recordingCollection().find(r => r.id === recordingUI.source);
const recordingBookmark = r => r.bookmarks.find(b => b.id === r.selected);
const bookmarkRange = (r, b) => ({start: Math.max(0, b.time - b.before), end: Math.min(r.duration, b.time + b.after)});
const recordingCuts = r => moments.filter(m => m.generated && m.originSession === state.session && m.source === r.id);
const pendingBookmarks = r => r.bookmarks.filter(b => !b.cutId && bookmarkRange(r, b).end > bookmarkRange(r, b).start);
const rsIcon = name => name === 'bookmark' ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4h12v17l-6-4-6 4Z"/></svg>' : name === 'cut' ? '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="6" r="3"/><circle cx="5" cy="18" r="3"/><path d="m7.5 7.5 13 12M7.5 16.5 20.5 4M14 10l-3 3"/></svg>' : icon(name);

function openRecording(source = recordingUI.source) {
  recordingUI.source = source;
  state.source = source;
  if(selected().originSession !== state.session || selected().source !== source) state.selected = sessionMoments().find(m=>m.source===source).id;
  recordingUI.playing = false;
  state.studioMode = 'recording';
  go('studio');
}
function openShot(id) {
  state.selected = Number(id);
  const m = selected();
  state.studioMode = 'shot';
  state.time = Math.min(m.duration || 8.4, m.bookmarkTime == null ? 2.4 : m.bookmarkTime - m.seconds);
  if (m.originSession) state.session = m.originSession;
  state.source = m.source;
  recordingUI.playing = false;
  go('studio');
}

function recordingStudio() {
  const r = currentRecording(), b = recordingBookmark(r), pending = pendingBookmarks(r), cuts = recordingCuts(r);
  return `<section class="rs-workspace" aria-labelledby="recording-title">
    <div class="rs-heading">
      <button class="back" data-action="nav" data-view="session" aria-label="Back to session">${icon('back')}</button>
      <div><p class="eyebrow">${state.session === 'coast' ? 'A morning by the sea' : 'An afternoon at the range'} / Studio</p><h1 id="recording-title">Find your shots.</h1></div>
      <span class="rs-original">${icon('lock')} Original kept</span>
    </div>
    <div class="rs-source-row" aria-label="Choose a recording">
      ${recordingCollection().map(item => `<button data-action="rs-source" data-source="${item.id}" class="rs-source ${r.id === item.id ? 'active' : ''}" aria-pressed="${r.id === item.id}"><span class="rs-source-icon">${icon('video')}</span><span><strong>Recording 0${item.id}</strong><small>${fmt(item.duration)} · ${item.bookmarks.length} ${item.bookmarks.length === 1 ? 'bookmark' : 'bookmarks'}</small></span>${r.id === item.id ? icon('check') : ''}</button>`).join('')}
    </div>
    <div class="rs-layout">
      <section class="rs-player" aria-label="Full recording">
        <div class="rs-picture"><img src="${r.asset}" alt="Fictional golf recording represented by a still image"><span class="rs-source-badge">RECORDING 0${r.id} <i></i> ${fmt(r.duration)}</span><span class="rs-still">Sample still · playback simulated</span></div>
        <div class="rs-transport">
          <div class="rs-play-controls"><button class="icon-button" data-action="rs-seek" data-seconds="-5" aria-label="Seek back 5 seconds"><span class="rs-seek-icon">↶<small>5</small></span></button><button class="rs-play" data-action="rs-play" aria-label="${recordingUI.playing ? 'Pause recording preview' : 'Play recording preview'}">${icon(recordingUI.playing ? 'pause' : 'play')}</button><button class="icon-button" data-action="rs-seek" data-seconds="5" aria-label="Seek forward 5 seconds"><span class="rs-seek-icon">↷<small>5</small></span></button></div>
          <span class="rs-time"><b id="rs-time">${fmt(r.time)}</b><span> / ${fmt(r.duration)}</span></span>
          <button class="rs-bookmark-button" data-action="rs-add">${rsIcon('bookmark')} <span>Bookmark <b id="rs-button-time">${fmt(r.time)}</b></span></button>
        </div>
        <div class="rs-overview">
          <div class="rs-overview-title"><span>Full recording</span><span>${r.bookmarks.length} ${r.bookmarks.length === 1 ? 'moment' : 'moments'} marked</span></div>
          <div class="rs-timeline"><div class="rs-timeline-strip" aria-hidden="true">${Array.from({length:12},() => `<img src="${r.asset}" alt="">`).join('')}</div>
            <div class="rs-marker-layer">${r.bookmarks.map((mark,i) => `<button class="rs-marker ${mark.id === r.selected ? 'active' : ''} ${mark.cutId ? 'created' : ''}" data-action="rs-mark" data-id="${mark.id}" style="left:clamp(0px,calc(${mark.time / r.duration * 100}% - 22px),calc(100% - 44px))" aria-label="Go to bookmark ${i+1} at ${fmt(mark.time)}"><span>${i+1}</span></button>`).join('')}</div>
            <div class="rs-playhead" id="rs-playhead" style="left:${r.time / r.duration * 100}%" aria-hidden="true"></div>
          </div>
          <input id="rs-scrub" type="range" min="0" max="${r.duration}" step="1" value="${r.time}" aria-label="Recording playhead in seconds" aria-valuetext="${fmt(r.time)} of ${fmt(r.duration)}">
          <div class="rs-ruler" aria-hidden="true"><span>00:00</span><span>${fmt(r.duration / 4)}</span><span>${fmt(r.duration / 2)}</span><span>${fmt(r.duration * .75)}</span><span>${fmt(r.duration)}</span></div>
        </div>
        <p class="rs-player-note">Find a swing. Bookmark the moment. We’ll leave room either side.</p>
        <div class="rs-keyboard"><span><kbd>B</kbd> bookmark</span><span><kbd>←</kbd><kbd>→</kbd> seek 5s</span><span><kbd>space</kbd> play / pause</span></div>
      </section>
      <aside class="rs-sidebar" aria-label="Bookmarks and created shots">
        <div class="rs-side-header"><span class="eyebrow">FROM THE FULL RECORDING</span><h2>The moments in between.</h2><p>A few seconds before. A little after. <br>A shot of its own.</p></div>
        <div class="rs-tabs" aria-label="Recording selection"><button data-action="rs-tab" data-tab="bookmarks" aria-pressed="${recordingUI.tab === 'bookmarks'}" class="${recordingUI.tab === 'bookmarks' ? 'active' : ''}">Bookmarks <span>${r.bookmarks.length}</span></button><button data-action="rs-tab" data-tab="shots" aria-pressed="${recordingUI.tab === 'shots'}" class="${recordingUI.tab === 'shots' ? 'active' : ''}">Shots <span>${cuts.length}</span></button></div>
        ${recordingUI.tab === 'bookmarks' ? bookmarkList(r, b) : createdShotList(r)}
        <div class="rs-create-bar"><div><strong>${pending.length ? `${pending.length} ${pending.length === 1 ? 'moment' : 'moments'} ready` : cuts.length ? `${cuts.length} ${cuts.length === 1 ? 'shot' : 'shots'} created` : 'Mark your first moment'}</strong><small>${pending.length ? 'Your full recording stays intact.' : 'Find another swing to keep going.'}</small></div><button class="primary" data-action="rs-create" ${pending.length ? '' : 'disabled'}>${rsIcon('cut')} Create ${pending.length || ''} ${pending.length === 1 ? 'shot' : 'shots'}</button></div>
      </aside>
    </div>
    <p class="rs-demo-note">Interactive design study. Bookmarks and cuts are sample metadata retained while this page stays open.</p>
  </section>`;
}

function bookmarkList(r, b) {
  return `<div class="rs-bookmark-list">${r.bookmarks.length ? r.bookmarks.map((item, i) => {
    const range = bookmarkRange(r, item);
    return `<div class="rs-bookmark-row ${item.id === r.selected ? 'active' : ''}"><button data-action="rs-mark" data-id="${item.id}" class="rs-mark-select" aria-pressed="${item.id === r.selected}"><span class="rs-index">${String(i+1).padStart(2,'0')}</span><span><strong>${fmt(item.time)}</strong><small>${item.cutId ? 'Shot created' : `${fmt(range.start)}–${fmt(range.end)} · ${range.end-range.start}s`}</small></span>${item.cutId ? icon('check') : rsIcon('bookmark')}</button><button class="rs-remove" data-action="rs-remove" data-id="${item.id}" aria-label="Remove bookmark at ${fmt(item.time)}">${icon('close')}</button></div>`;
  }).join('') : '<div class="rs-empty">Your next good swing is in here.<br>Bookmark it while you watch.</div>'}</div>
  ${b ? bookmarkEditor(r,b) : ''}
  ${recordingUI.undo?.session === state.session && recordingUI.undo?.source === r.id ? '<button class="text-button rs-undo" data-action="rs-undo">'+icon('undo')+' Undo removed bookmark</button>' : ''}`;
}

function bookmarkEditor(r, b) {
  const range = bookmarkRange(r, b), length = range.end - range.start;
  const clipped = b.time - b.before < 0 || b.time + b.after > r.duration;
  return `<section class="rs-window" aria-label="Clip around selected bookmark"><div class="rs-window-heading"><strong>${b.cutId ? 'Created from this moment' : 'A little room either side.'}</strong><span>${fmt(b.time)}</span></div>
    <div class="rs-window-preview" aria-hidden="true"><div class="rs-window-before" style="flex:${b.time-range.start || .08}"></div><span></span><div class="rs-window-after" style="flex:${range.end-b.time || .08}"></div></div>
    <div class="rs-window-labels"><span>${fmt(range.start)}</span><b>${length}s shot</b><span>${fmt(range.end)}</span></div>
    ${b.cutId ? `<p class="rs-window-hint">The shot is ready. Keep refining its trim, trace and format in Shot Studio.</p><button class="secondary rs-refine" data-action="rs-open-cut" data-id="${b.cutId}">Refine this shot ${icon('arrow')}</button>` : `<div class="rs-buffers">${bufferControl(b,'before','Before the moment')}${bufferControl(b,'after','After the moment')}</div><p class="rs-window-hint">${length === 0 ? 'Add at least 1 second before or after this bookmark.' : clipped ? 'Trimmed to the edge of the original recording.' : 'Starts 5 seconds either side by default. Make this shot as short or as roomy as you like.'}</p>`}
  </section>`;
}
function bufferControl(b, side, label) {
  return `<div class="rs-buffer"><span>${label}</span><div><button data-action="rs-buffer" data-side="${side}" data-delta="-1" aria-label="Reduce seconds ${side}" ${b[side] === 0 ? 'disabled' : ''}>−</button><output aria-label="Seconds ${side}">${b[side]}<small>s</small></output><button data-action="rs-buffer" data-side="${side}" data-delta="1" aria-label="Increase seconds ${side}" ${b[side] === 30 ? 'disabled' : ''}>+</button></div></div>`;
}
function createdShotList(r) {
  const cuts = recordingCuts(r);
  return `<div class="rs-cuts">${cuts.length ? `<p class="rs-cut-intro">${cuts.length} individual ${cuts.length === 1 ? 'shot' : 'shots'}, ready to make yours.</p>${cuts.map((m, i) => `<button class="rs-cut-card" data-action="rs-open-cut" data-id="${m.id}"><span class="rs-cut-image"><img src="${m.asset}" alt="Sample shot thumbnail"><b>${(m.end-m.start).toFixed(1).replace(/\.0$/,'')}s</b></span><span><strong>${escapeHTML(m.title || `Shot ${String(i+1).padStart(2,'0')}`)}</strong><small>${fmt(m.seconds+m.start)}–${fmt(m.seconds+m.end)}</small><span class="rs-cut-link">Trim, trace & format ${icon('arrow')}</span></span></button>`).join('')}` : `<div class="rs-empty">Your shots will live here.<br>Mark a few moments, then create your clips.</div>`}</div>`;
}

function updateRecordingPlayhead() {
  const r = currentRecording();
  for (const id of ['rs-time','rs-button-time']) { const el = document.getElementById(id); if (el) el.textContent = fmt(r.time); }
  const input = document.getElementById('rs-scrub');
  if (input) { input.value = r.time; input.setAttribute('aria-valuetext', `${fmt(r.time)} of ${fmt(r.duration)}`); }
  const head = document.getElementById('rs-playhead');
  if (head) head.style.left = `${r.time / r.duration * 100}%`;
}
function addRecordingBookmark() {
  const r = currentRecording();
  const exists = r.bookmarks.find(b => Math.abs(b.time - r.time) < 1);
  recordingUI.tab = 'bookmarks';
  if (exists) { r.selected = exists.id; render(); toast('This moment is already bookmarked.'); return; }
  const b = {id:`manual-${++recordingUI.serial}`,time:Math.round(r.time),before:5,after:5,cutId:null};
  r.bookmarks.push(b); r.bookmarks.sort((a,b) => a.time-b.time); r.selected=b.id;
  render(); const range=bookmarkRange(r,b);toast(`Bookmarked ${fmt(b.time)}. ${range.end-range.start} seconds ready to make a shot.`);
}
function createRecordingShots() {
  const r = currentRecording(), pending = pendingBookmarks(r);
  if (!pending.length) return;
  pending.forEach(b => {
    const range = bookmarkRange(r,b), id = Math.max(...moments.map(m=>m.id)) + 1;
    const ordinal = recordingCuts(r).length + 1;
    moments.push({id,club:'Shot',source:r.id,seconds:range.start,sourceEnd:range.end,bookmarkTime:b.time,bookmarkId:b.id,
      generated:true,originSession:state.session,duration:range.end-range.start,asset:r.asset,kept:false,confirmed:true,skipped:false,
      trace:false,colour:'#e8f1b8',format:'original',start:0,end:range.end-range.start,title:`Shot ${String(ordinal).padStart(2,'0')}`});
    b.cutId=id;
  });
  recordingUI.tab='shots'; recordingUI.playing=false;
  render();
  if (window.innerWidth <= 620) document.querySelector('.rs-sidebar')?.scrollIntoView({block:'start',behavior:'instant'});
  toast(`${pending.length} ${pending.length === 1 ? 'shot' : 'shots'} created in this prototype. Original recording retained.`);
}
document.addEventListener('click',e => {
  const button=e.target.closest('[data-action^="rs-"]');
  if (!button || button.disabled) return;
  const a=button.dataset.action;
  if (a==='rs-return') { const m=selected(); if(m.originSession)state.session=m.originSession;recordingUI.tab='shots';openRecording(m.source);return; }
  const r=currentRecording(), b=recordingBookmark(r);
  if(a==='rs-source') { openRecording(Number(button.dataset.source)); }
  else if(a==='rs-add') addRecordingBookmark();
  else if(a==='rs-seek') {r.time=Math.max(0,Math.min(r.duration,r.time+Number(button.dataset.seconds)));updateRecordingPlayhead();}
  else if(a==='rs-play') {recordingUI.playing=!recordingUI.playing;if(r.time>=r.duration)r.time=0;render();}
  else if(a==='rs-mark') {const mark=r.bookmarks.find(m=>m.id===button.dataset.id);r.selected=mark.id;r.time=mark.time;recordingUI.playing=false;recordingUI.tab='bookmarks';render();}
  else if(a==='rs-tab') {recordingUI.tab=button.dataset.tab;render();}
  else if(a==='rs-buffer' && b && !b.cutId) {const side=button.dataset.side;b[side]=Math.max(0,Math.min(30,b[side]+Number(button.dataset.delta)));render();}
  else if(a==='rs-remove') {const index=r.bookmarks.findIndex(m=>m.id===button.dataset.id);recordingUI.undo={session:state.session,source:r.id,bookmark:r.bookmarks[index]};r.bookmarks.splice(index,1);if(!recordingBookmark(r))r.selected=r.bookmarks[Math.min(index,r.bookmarks.length-1)]?.id;render();toast('Bookmark removed. Any shot already created is kept.');}
  else if(a==='rs-undo') {const removed=recordingUI.undo;if(removed){r.bookmarks.push(removed.bookmark);r.bookmarks.sort((a,b)=>a.time-b.time);r.selected=removed.bookmark.id;recordingUI.undo=null;render();toast('Bookmark restored.');}}
  else if(a==='rs-create') createRecordingShots();
  else if(a==='rs-open-cut') openShot(button.dataset.id);
});
document.addEventListener('input',e=>{if(e.target.id==='rs-scrub'){currentRecording().time=Number(e.target.value);recordingUI.playing=false;updateRecordingPlayhead();const button=document.querySelector('[data-action="rs-play"]');if(button){button.innerHTML=icon('play');button.setAttribute('aria-label','Play recording preview');}}});
document.addEventListener('keydown',e=>{
  if(state.view!=='studio'||state.studioMode!=='recording'||sheet.open||e.ctrlKey||e.metaKey||e.altKey||e.target.closest('input,textarea,select,[contenteditable]'))return;
  if(e.key.toLowerCase()==='b'){e.preventDefault();addRecordingBookmark();}
  else if(e.key==='ArrowLeft'||e.key==='ArrowRight'){e.preventDefault();const r=currentRecording();r.time=Math.max(0,Math.min(r.duration,r.time+(e.key==='ArrowLeft'?-5:5)));updateRecordingPlayhead();}
  else if(e.code==='Space'&&!e.target.closest('button')){e.preventDefault();recordingUI.playing=!recordingUI.playing;render();}
});
setInterval(()=>{if(!recordingUI.playing||state.view!=='studio'||state.studioMode!=='recording'||document.hidden)return;const r=currentRecording();r.time=Math.min(r.duration,r.time+1);updateRecordingPlayhead();if(r.time>=r.duration){recordingUI.playing=false;render();}},1000);
