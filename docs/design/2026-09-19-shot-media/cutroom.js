(() => {
  'use strict';

  const paths = {
    plus: '<path d="M12 5v14M5 12h14"/>',
    arrow: '<path d="M5 12h14m-5-5 5 5-5 5"/>',
    upRight: '<path d="M6 18 18 6M6 6h12v12"/>',
    back: '<path d="m14 6-6 6 6 6"/>',
    next: '<path d="m10 6 6 6-6 6"/>',
    sessions: '<rect x="4" y="6" width="16" height="14" rx="2"/><path d="M8 3h8M4 11h16"/>',
    shots: '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="m10 8 6 4-6 4z"/>',
    film: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M7 5v14M17 5v14M3 10h4m-4 4h4m10-4h4m-4 4h4"/>',
    star: '<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9z"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    play: '<path d="m8 4 12 8-12 8z" fill="currentColor" stroke="none"/>',
    pause: '<path d="M8 5v14M16 5v14" stroke-width="3"/>',
    previousFrame: '<path d="M6 5v14m12-14-8 7 8 7z"/>',
    nextFrame: '<path d="M18 5v14M6 5l8 7-8 7z"/>',
    trim: '<path d="M6 3v18M18 3v18M3 7h18M3 17h18"/>',
    trace: '<path d="M3 19C7 7 15 2 20 6"/><circle cx="3" cy="19" r="1.5"/><circle cx="20" cy="6" r="1.5"/>',
    format: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8v8H8z"/>',
    export: '<path d="M5 14v6h14v-6M12 16V3m-5 5 5-5 5 5"/>',
    sound: '<path d="m11 5-6 4H2v6h3l6 4zM15 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
    undo: '<path d="M4 5v6h6M4 11a8 8 0 1 1 2 8"/>',
    download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
    spark: '<path d="m12 3 2.3 6.7L21 12l-6.7 2.3L12 21l-2.3-6.7L3 12l6.7-2.3z"/>',
    fit: '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5M8 8h8v8H8z"/>',
    eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>'
  };
  const icon = (name, extra = '') => `<svg class="icon ${extra}" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.arrow}</svg>`;
  const mark = '<svg class="brand-mark" viewBox="0 0 32 32" aria-hidden="true"><path d="M7 24V15C7 8 11 4 17 4c4.5 0 8 3 8 7s-3.5 7-8 7h-5" fill="none" stroke="currentColor" stroke-width="4.5"/><circle cx="25" cy="25" r="3.2" fill="currentColor"/></svg>';
  const photo = name => `assets/${name}.png`;
  const sessions = [
    { id: 'friday', title: 'The Friday bucket', place: 'Nine Pines Range', date: 'Friday, 18 Sep', shortDate: '18 SEP 2026', time: '5:24 pm', image: 'range', recordings: 3, sourceDuration: '18:42' },
    { id: 'coast', title: 'One more at the coast', place: 'North Head Links', date: 'Sunday, 13 Sep', shortDate: '13 SEP 2026', time: '3:08 pm', image: 'course', recordings: 2, sourceDuration: '07:36' },
    { id: 'early', title: 'Before the day begins', place: 'Nine Pines Range', date: 'Tuesday, 8 Sep', shortDate: '08 SEP 2026', time: '6:41 am', image: 'range', recordings: 1, sourceDuration: '09:12' }
  ];
  const moments = [
    { id: 'f1', session: 'friday', title: 'First ball feeling', recording: 1, start: 12, duration: 7, saved: false, keeper: false, skipped: false, position: '40% 50%' },
    { id: 'f2', session: 'friday', title: 'A little left', recording: 1, start: 28, duration: 6, saved: false, keeper: false, skipped: false, position: '55% 50%' },
    { id: 'f3', session: 'friday', title: 'That finish.', recording: 1, start: 47, duration: 8, saved: true, keeper: true, skipped: false, position: '40% 52%', trace: true },
    { id: 'f4', session: 'friday', title: 'The clean one', recording: 2, start: 74, duration: 9, saved: true, keeper: false, skipped: false, position: '60% 50%' },
    { id: 'f5', session: 'friday', title: 'Finding rhythm', recording: 2, start: 98, duration: 7, saved: false, keeper: false, skipped: false, position: '30% 50%' },
    { id: 'f6', session: 'friday', title: 'One to remember', recording: 2, start: 121, duration: 8, saved: false, keeper: false, skipped: false, position: '65% 45%' },
    { id: 'f7', session: 'friday', title: 'Just one more', recording: 3, start: 42, duration: 6, saved: false, keeper: false, skipped: false, position: '45% 55%' },
    { id: 'f8', session: 'friday', title: 'Last ball energy', recording: 3, start: 69, duration: 9, saved: true, keeper: true, skipped: false, position: '50% 50%' },
    { id: 'c1', session: 'coast', title: 'A view worth keeping', recording: 1, start: 18, duration: 9, saved: true, keeper: true, skipped: false, position: '30% 50%', trace: true },
    { id: 'c2', session: 'coast', title: 'Into the afternoon', recording: 1, start: 38, duration: 7, saved: false, keeper: false, skipped: false, position: '60% 50%' },
    { id: 'c3', session: 'coast', title: 'Right down the middle', recording: 2, start: 25, duration: 8, saved: true, keeper: false, skipped: false, position: '50% 50%' },
    { id: 'e1', session: 'early', title: 'Before the rush', recording: 1, start: 35, duration: 8, saved: true, keeper: false, skipped: false, position: '40% 50%' },
    { id: 'e2', session: 'early', title: 'Morning rhythm', recording: 1, start: 64, duration: 7, saved: false, keeper: false, skipped: false, position: '60% 50%' }
  ];
  const state = { view: 'sessions', detail: false, session: 'friday', selected: 'f3', filter: 'all', recording: 'all', shotsFilter: 'all', tool: 'trim', returnView: 'sessions', importType: 'range', importSession: 'friday', playing: false, time: 2.8 };
  const drafts = new Map();
  const app = document.getElementById('app');
  const dialog = document.getElementById('app-dialog');
  const toastElement = document.getElementById('toast');
  let toastTimer;
  let playbackTimer;
  let importCount = 0;
  let previousDialogFocus;

  const sessionById = id => sessions.find(s => s.id === id) || sessions[0];
  const currentSession = () => sessionById(state.session);
  const currentMoment = () => moments.find(m => m.id === state.selected) || moments[2];
  const sessionMoments = id => moments.filter(m => m.session === id);
  const momentIndex = m => sessionMoments(m.session).findIndex(x => x.id === m.id) + 1;
  const pad = number => String(number).padStart(2, '0');
  const seconds = value => `${pad(Math.floor(value / 60))}:${pad(Math.floor(value % 60))}`;
  const durationText = value => `${Number(value.toFixed(1))}s`;
  const counted = (number, word) => `${number} ${word}${number === 1 ? '' : 's'}`;
  const formatName = format => ({ original: 'Original', portrait: '9:16', square: '1:1' })[format];
  const escape = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

  function draftFor(moment) {
    if (!drafts.has(moment.id)) drafts.set(moment.id, { start: 0, end: moment.duration, format: 'original', trace: Boolean(moment.trace), colour: '#355cf5' });
    return drafts.get(moment.id);
  }

  function toast(message) {
    clearTimeout(toastTimer);
    toastElement.textContent = message;
    toastElement.classList.add('visible');
    toastTimer = setTimeout(() => toastElement.classList.remove('visible'), 3600);
  }

  function stopPlayback() {
    state.playing = false;
    clearInterval(playbackTimer);
    const playButton = document.querySelector('[data-action="play"]');
    if (playButton) { playButton.innerHTML = icon('play'); playButton.setAttribute('aria-label', 'Play sample timeline'); }
  }

  function header() {
    return `<header class="app-header">
      <button class="brand" data-action="nav" data-view="sessions" aria-label="Ronde, sessions">${mark}<span class="brand-name">ronde</span></button>
      <nav class="top-nav" aria-label="Main navigation"><button data-action="nav" data-view="sessions" class="${state.view === 'sessions' ? 'active' : ''}" ${state.view === 'sessions' ? 'aria-current="page"' : ''}>Sessions</button><button data-action="nav" data-view="shots" class="${state.view === 'shots' ? 'active' : ''}" ${state.view === 'shots' ? 'aria-current="page"' : ''}>Shots</button></nav>
      <div class="header-end"><span class="local-note">On this device</span><button class="header-about" data-action="about" aria-label="About this sample prototype">i</button><button class="primary" data-action="import">${icon('plus')}Add recording</button></div>
    </header>`;
  }

  function bottomNav() {
    return `<nav class="bottom-nav" aria-label="Main navigation"><button class="nav-item ${state.view === 'sessions' ? 'active' : ''}" data-action="nav" data-view="sessions" ${state.view === 'sessions' ? 'aria-current="page"' : ''}>${icon('sessions')}<span>Sessions</span></button><button class="nav-item ${state.view === 'shots' ? 'active' : ''}" data-action="nav" data-view="shots" ${state.view === 'shots' ? 'aria-current="page"' : ''}>${icon('shots')}<span>Shots</span></button><button class="primary" data-action="import">${icon('plus')}Add recording</button></nav>`;
  }

  function sessionRail() {
    return `<aside class="session-rail" aria-label="Your sessions"><div class="rail-title"><h1>Sessions</h1><button class="icon-button" data-action="import" aria-label="Add a recording to a session">${icon('plus')}</button></div>${sessions.map(s => `<button class="rail-session ${s.id === state.session ? 'active' : ''}" data-action="session" data-id="${s.id}" ${s.id === state.session ? 'aria-current="true"' : ''}><img src="${photo(s.image)}" alt="" loading="eager"><span class="eyebrow">${s.shortDate}</span><strong>${s.title}</strong><small>${counted(s.recordings, 'recording')} · ${counted(sessionMoments(s.id).filter(m => m.saved).length, 'shot')}</small></button>`).join('')}<div class="rail-footer">${icon('lock')}<p>Your originals.<br>Your best moments.<br>Always yours.</p><span class="sample-note">FICTIONAL SAMPLE LIBRARY</span></div></aside>`;
  }

  function mobileHome() {
    const latest = sessions[0];
    return `<section class="mobile-home subtle-entrance" aria-label="Session collection"><p class="eyebrow">Make something of your game</p><h1>Sessions.</h1><div class="home-section-label"><span class="eyebrow">The latest</span><span>${latest.date}</span></div><button class="session-hero" data-action="session" data-id="${latest.id}" aria-label="Open The Friday bucket, ${counted(latest.recordings, 'recording')}"><div class="session-cover"><img src="${photo(latest.image)}" alt="Golfer at a quiet range in the late afternoon"><span class="cover-stamp">${pad(latest.recordings)} RECORDINGS</span><span class="cover-mark">${icon('upRight')}</span></div><div class="session-caption"><h2>${latest.title}</h2><p>${latest.place} · ${latest.time}</p><span class="session-review">${sessionMoments(latest.id).length} moments. Find your favourites. ${icon('arrow')}</span></div></button><div class="home-older"><div class="home-section-label"><span class="eyebrow">The rest of the roll</span><span>September</span></div>${sessions.slice(1).map(s => `<button class="old-session" data-action="session" data-id="${s.id}"><img src="${photo(s.image)}" alt=""><span><strong>${s.title}</strong><small>${s.date} · ${counted(s.recordings, 'recording')}</small></span>${icon('next')}</button>`).join('')}</div><p class="home-footnote">${icon('lock')}A private home for the shots worth keeping.</p><span class="sample-note">SAMPLE SESSIONS · FICTIONAL MEDIA</span></section>`;
  }

  function filteredMoments() {
    return sessionMoments(state.session).filter(m => (state.recording === 'all' || m.recording === Number(state.recording)) && (state.filter === 'all' ? !m.skipped : state.filter === 'review' ? !m.saved && !m.skipped : state.filter === 'shots' ? m.saved && !m.skipped : m.skipped));
  }

  function momentCard(moment, shot = false) {
    const session = sessionById(moment.session);
    const index = momentIndex(moment);
    return `<article class="moment-card ${moment.id === state.selected && !shot ? 'selected' : ''}"><button class="moment-open" data-action="${shot ? 'studio' : 'select'}" data-id="${moment.id}" aria-label="${shot ? 'Edit shot' : 'Review moment'} ${pad(index)}: ${moment.title}"><div class="moment-image"><img src="${photo(moment.image || session.image)}" alt="Fictional golf recording at ${session.place}" style="object-position:${moment.position}" loading="eager"><span class="moment-index">${pad(index)}</span><span class="moment-state">${moment.skipped ? 'SKIPPED' : moment.saved ? icon('check') + 'SAVED SHOT' : ''}</span><span class="moment-duration">0:${pad(moment.duration)}</span></div><span class="moment-name">${moment.title}${icon('upRight')}</span><span class="moment-source">${shot ? session.title : `REC ${pad(moment.recording)} · ${seconds(moment.start)}–${seconds(moment.start + moment.duration)}`}</span></button><button class="moment-star ${moment.keeper ? 'active' : ''}" data-action="keeper" data-id="${moment.id}" aria-label="${moment.keeper ? 'Remove from' : 'Add to'} Keepers: ${moment.title}" aria-pressed="${moment.keeper}">${icon('star')}</button></article>`;
  }

  function previewPanel() {
    const moment = currentMoment();
    const session = sessionById(moment.session);
    return `<aside class="preview-panel" aria-label="Selected moment"><div class="preview-topline"><span class="eyebrow">In focus</span><span>${pad(momentIndex(moment))} / ${pad(sessionMoments(moment.session).length)}</span></div><button class="preview-image" data-action="studio" data-id="${moment.id}" aria-label="Open ${moment.title} in Studio"><img src="${photo(moment.image || session.image)}" alt="Full sample source frame"><span class="preview-tag">MOMENT ${pad(momentIndex(moment))} · ${durationText(moment.duration)}</span></button><h2>${moment.title}</h2><p class="source-time">REC ${pad(moment.recording)} · ${seconds(moment.start)}–${seconds(moment.start + moment.duration)}</p><button class="primary" data-action="studio" data-id="${moment.id}">Open in Studio ${icon('upRight')}</button><div class="preview-actions"><button class="text-button ${moment.saved ? 'saved' : ''}" data-action="save-shot" data-id="${moment.id}">${icon(moment.saved ? 'check' : 'plus')}${moment.saved ? 'Saved to Shots' : 'Save as shot'}</button><button class="text-button" data-action="skip" data-id="${moment.id}">${icon(moment.skipped ? 'undo' : 'next')}${moment.skipped ? 'Restore' : 'Skip'}</button></div><p class="preview-help"><strong>A good moment deserves a second look.</strong><br>Keep it, trim it, make it yours.</p><div class="preview-steps"><span>SELECT A MOMENT</span><div><button class="icon-button" data-action="step" data-direction="-1" aria-label="Previous moment">${icon('back')}</button><button class="icon-button" data-action="step" data-direction="1" aria-label="Next moment">${icon('next')}</button></div></div></aside>`;
  }

  function sessionView() {
    const session = currentSession();
    const visible = filteredMoments();
    return `<main id="main-content" class="shell ${state.detail ? 'is-detail' : ''}">${sessionRail()}${mobileHome()}<section class="session-main subtle-entrance" aria-label="Session contact sheet"><button class="mobile-back" data-action="session-back">${icon('back')}All sessions</button><div class="page-heading"><div><p class="eyebrow blue">Session ${pad(sessions.findIndex(s => s.id === session.id) + 1)} / Sample session</p><h1>${session.title}</h1><p>${session.place} <span aria-hidden="true">/</span> ${session.date} <span aria-hidden="true">/</span> ${session.time}</p></div><div class="session-heading-actions"><span class="source-count">${pad(session.recordings)} ${session.recordings === 1 ? 'RECORDING' : 'RECORDINGS'}<br>${session.sourceDuration} OF ORIGINALS</span><button class="icon-button session-switch" data-action="session-switch" aria-label="Switch session">${icon('sessions')}</button></div></div><div class="recording-tabs" role="group" aria-label="Recordings"><button data-action="recording" data-recording="all" class="${state.recording === 'all' ? 'active' : ''}" aria-pressed="${state.recording === 'all'}">${icon('film')}All recordings</button>${Array.from({ length: session.recordings }, (_, index) => `<button data-action="recording" data-recording="${index + 1}" class="${Number(state.recording) === index + 1 ? 'active' : ''}" aria-pressed="${Number(state.recording) === index + 1}">Recording ${pad(index + 1)}</button>`).join('')}</div><div class="collection-line"><div class="filter-group" role="group" aria-label="Filter moments">${[['all', 'All moments'], ['review', 'To review'], ['shots', 'Shots'], ['skipped', 'Skipped']].map(([value, label]) => `<button data-action="filter" data-filter="${value}" class="${state.filter === value ? 'active' : ''}" aria-pressed="${state.filter === value}">${label}</button>`).join('')}</div><span class="sheet-count">${pad(visible.length)} IN VIEW</span></div><div class="review-workspace"><div class="contact-sheet">${visible.length ? visible.map(m => momentCard(m)).join('') : `<div class="empty-state">${icon('check')}<strong>${state.filter === 'skipped' ? 'Nothing skipped.' : 'A clear contact sheet.'}</strong><p>${state.filter === 'skipped' ? 'Skipped moments live here. Your original recordings always stay intact.' : 'Try another recording or return to all moments.'}</p><button class="secondary" data-action="clear-filters">Show all moments</button></div>`}</div>${previewPanel()}</div></section></main>`;
  }

  function shotsView() {
    const shots = moments.filter(m => m.saved && !m.skipped && (state.shotsFilter === 'keepers' ? m.keeper : true));
    return `<main id="main-content" class="shots-main subtle-entrance"><div class="shots-title"><div><p class="eyebrow blue">Your shot collection</p><h1>The good stuff.</h1></div><p>The shots you came back to.<br>Ready for a little finishing touch.</p></div><div class="shots-filter"><div class="filter-group" role="group" aria-label="Filter your shots"><button data-action="shots-filter" data-filter="all" class="${state.shotsFilter === 'all' ? 'active' : ''}" aria-pressed="${state.shotsFilter === 'all'}">All shots</button><button data-action="shots-filter" data-filter="keepers" class="${state.shotsFilter === 'keepers' ? 'active' : ''}" aria-pressed="${state.shotsFilter === 'keepers'}">Keepers</button></div><span class="eyebrow">${pad(shots.length)} SELECTED MOMENTS</span></div><div class="shot-gallery">${shots.length ? shots.map(m => momentCard(m, true)).join('') : `<div class="empty-state">${icon('star')}<strong>Your favourites belong here.</strong><p>Star a shot to add it to Keepers.</p><button class="secondary" data-action="shots-filter" data-filter="all">See all shots</button></div>`}</div><span class="sample-note">FICTIONAL SAMPLE SHOTS · ORIGINALS KEPT INTACT</span></main>`;
  }

  function manualTrace(draft) {
    return draft.trace ? `<svg class="manual-trace" viewBox="0 0 900 600" preserveAspectRatio="xMidYMid meet" aria-hidden="true"><path class="trace-base" d="M362 472C422 335 548 155 660 108C700 92 730 106 746 141"/><path class="trace-colour" style="stroke:${draft.colour}" d="M362 472C422 335 548 155 660 108C700 92 730 106 746 141"/></svg><span class="trace-provenance">MANUAL TRACE</span>` : '';
  }

  function canvas(moment, draft) {
    const session = sessionById(moment.session);
    return `<div class="format-canvas format-${draft.format}"><div class="source-fit"><img src="${photo(moment.image || session.image)}" alt="Fitted, uncropped sample golf source frame">${manualTrace(draft)}</div></div>`;
  }

  function toolPanel() {
    const moment = currentMoment();
    const draft = draftFor(moment);
    if (state.tool === 'trace') return `<section class="tool-panel"><p class="eyebrow blue">02 / Trace</p><h2>Give it a line.</h2><p class="tool-description">A finishing touch, with the source of the line always clear.</p><div class="toggle-row"><span><strong>Manual trace</strong><small>Fictional sample annotation</small></span><button class="toggle" data-action="trace-toggle" role="switch" aria-checked="${draft.trace}" aria-label="Show manual trace"><span class="toggle-track"><span class="toggle-knob"></span></span></button></div><p class="trace-explanation">This line is an illustration, not an observed flight path. The “Manual trace” label stays with the export.</p><div class="trace-swatch-row" role="group" aria-label="Manual trace colour">${[['#355cf5','Cobalt'],['#ffffff','White'],['#dbfb72','Lime']].map(([colour, name]) => `<button class="trace-swatch ${draft.colour === colour ? 'active' : ''}" data-action="trace-colour" data-colour="${colour}" aria-label="${name} trace" aria-pressed="${draft.colour === colour}" style="--swatch:${colour}"><span></span></button>`).join('')}</div></section>`;
    if (state.tool === 'format') return `<section class="tool-panel"><p class="eyebrow blue">03 / Format</p><h2>Find your frame.</h2><p class="tool-description">A reel, a post, or just the original. The whole shot comes with you.</p><div class="format-options" role="group" aria-label="Output aspect ratio">${[['original','Original'],['portrait','9:16'],['square','1:1']].map(([format, label]) => `<button class="format-option ${draft.format === format ? 'active' : ''}" data-action="format" data-format="${format}" aria-pressed="${draft.format === format}"><span class="format-icon ${format}"></span>${label}</button>`).join('')}</div><p class="fit-note">${icon('fit')}Your entire source is fitted into the frame. Nothing is cropped or stretched.</p></section>`;
    return `<section class="tool-panel"><p class="eyebrow blue">01 / Trim</p><h2>Just the good bit.</h2><p class="tool-description">Leave a little room before the swing. Let the finish have its moment.</p><div class="range-row"><label for="trim-start">Start <output id="trim-start-value">${draft.start.toFixed(1)}s</output></label><input id="trim-start" type="range" min="0" max="${moment.duration - 1}" step="0.1" value="${draft.start}" data-input="trim-start"></div><div class="range-row"><label for="trim-end">End <output id="trim-end-value">${draft.end.toFixed(1)}s</output></label><input id="trim-end" type="range" min="1" max="${moment.duration}" step="0.1" value="${draft.end}" data-input="trim-end"></div><div class="trim-summary"><span>Your clip</span><strong id="trim-duration">${durationText(draft.end - draft.start)}</strong></div><button class="reset-edit" data-action="reset-trim">Restore full moment</button></section>`;
  }

  function studioView() {
    const moment = currentMoment();
    const session = sessionById(moment.session);
    const draft = draftFor(moment);
    state.time = Math.max(draft.start, Math.min(draft.end, state.time));
    return `<main id="main-content" class="studio subtle-entrance"><div class="studio-heading"><div class="studio-heading-left"><button class="icon-button" data-action="studio-back" aria-label="Back to ${state.returnView === 'shots' ? 'Shots' : 'session contact sheet'}">${icon('back')}</button><div><h1>${moment.title}</h1><p class="eyebrow">${session.title} / ${moment.saved ? 'Shot' : 'Moment'} ${pad(momentIndex(moment))}</p></div></div><div class="studio-heading-actions"><button class="keeper-button ${moment.keeper ? 'active' : ''}" data-action="keeper" data-id="${moment.id}" aria-label="${moment.keeper ? 'Remove from' : 'Add to'} Keepers" aria-pressed="${moment.keeper}">${icon('star')}<span>Keeper</span></button><button class="primary" data-action="export">Export ${icon('export')}</button></div></div><div class="studio-layout"><section class="studio-media-column" aria-label="Shot preview"><div class="stage-topline"><span class="eyebrow">Shot Studio</span><span class="stage-tag">${icon('eye')}Sample preview</span></div><div class="stage" id="studio-stage">${canvas(moment, draft)}</div><div class="stage-annotation"><span>${icon('fit')}Full source fitted · <b id="stage-format">${formatName(draft.format)}</b></span><span id="trace-status">${draft.trace ? 'Manual trace' : 'No trace applied'}</span></div><div class="transport"><div class="timecode"><strong id="current-time">${state.time.toFixed(1)}s</strong> / ${moment.duration.toFixed(1)}s</div><div class="transport-controls"><button class="icon-button" data-action="frame" data-direction="-1" aria-label="Step sample timeline backwards">${icon('previousFrame')}</button><button class="icon-button play-button" data-action="play" aria-label="${state.playing ? 'Pause' : 'Play'} sample timeline">${icon(state.playing ? 'pause' : 'play')}</button><button class="icon-button" data-action="frame" data-direction="1" aria-label="Step sample timeline forwards">${icon('nextFrame')}</button></div><span class="transport-end">REC ${pad(moment.recording)} · ${seconds(moment.start)}</span></div><input class="scrub-control" type="range" min="0" max="${moment.duration}" step="0.1" value="${state.time}" data-input="scrub" aria-label="Scrub sample shot timeline"><div class="filmstrip" aria-hidden="true">${Array.from({ length: 8 }, (_, index) => `<img src="${photo(moment.image || session.image)}" alt="" style="object-position:${30 + index * 7}% 50%">`).join('')}<span class="filmstrip-playhead" id="filmstrip-playhead" style="left:${state.time / moment.duration * 100}%"></span></div><div class="timeline-scale"><span>00:00</span><span>${seconds(moment.duration / 3)}</span><span>${seconds(moment.duration * 2 / 3)}</span><span>${seconds(moment.duration)}</span></div><div class="timeline-footer"><p>${moment.saved ? 'Saved in your shot collection.' : 'Found a good one? Add it to your shots.'}</p><div class="studio-review-actions"><button class="text-button" data-action="save-shot" data-id="${moment.id}">${icon(moment.saved ? 'check' : 'plus')}${moment.saved ? 'Saved to Shots' : 'Save shot'}</button><button class="text-button" data-action="skip" data-id="${moment.id}">${icon(moment.skipped ? 'undo' : 'next')}${moment.skipped ? 'Restore' : 'Skip'}</button></div></div></section><aside class="inspector" aria-label="Editing tools"><div class="tool-tabs" role="tablist" aria-label="Edit shot">${[['trim','Trim'],['trace','Trace'],['format','Format']].map(([tool,label]) => `<button id="tab-${tool}" role="tab" aria-selected="${state.tool === tool}" aria-controls="tool-content" tabindex="${state.tool === tool ? '0' : '-1'}" data-action="tool" data-tool="${tool}" class="${state.tool === tool ? 'active' : ''}">${icon(tool)}${label}</button>`).join('')}</div><div id="tool-content" role="tabpanel" aria-labelledby="tab-${state.tool}">${toolPanel()}</div><div class="inspector-footer"><p class="source-note">${icon('lock')}Edits leave your original untouched.<br>Come back and change your mind.</p><p class="sample-note-studio">SAMPLE MEDIA · EDITS LAST FOR THIS PREVIEW</p></div></aside></div></main>`;
  }

  function render() {
    const focused = document.activeElement;
    const focusData = focused?.matches('button[data-action]') ? { ...focused.dataset } : null;
    app.innerHTML = header() + (state.view === 'studio' ? studioView() : state.view === 'shots' ? shotsView() : sessionView()) + bottomNav();
    if (focusData && !dialog.open) {
      const replacement = Array.from(app.querySelectorAll('button[data-action]')).find(button => button.offsetParent !== null && Object.entries(focusData).every(([key, value]) => button.dataset[key] === value));
      replacement?.focus({ preventScroll: true });
    }
    document.title = `Ronde · ${state.view === 'studio' ? 'Shot Studio' : state.view === 'shots' ? 'Shots' : 'Sessions'} · Cutroom`;
  }

  function navigate(view, scroll = true) {
    stopPlayback();
    if (view === 'studio') {
      if (state.view !== 'studio') state.returnView = state.view;
      state.session = currentMoment().session;
    }
    if (view === 'sessions') state.detail = false;
    state.view = view;
    render();
    if (scroll) window.scrollTo({ top: 0, behavior: 'instant' });
  }

  function selectSession(id) {
    stopPlayback();
    state.view = 'sessions';
    state.session = id;
    state.detail = true;
    state.filter = 'all';
    state.recording = 'all';
    state.selected = sessionMoments(id).find(m => m.keeper)?.id || sessionMoments(id)[0].id;
    render();
    window.scrollTo({ top: 0, behavior: 'instant' });
  }

  function openStudio(id) {
    stopPlayback();
    state.returnView = state.view === 'shots' ? 'shots' : 'sessions';
    state.selected = id;
    state.session = currentMoment().session;
    state.time = draftFor(currentMoment()).start + .3;
    state.view = 'studio';
    render();
    window.scrollTo({ top: 0, behavior: 'instant' });
  }

  function refreshStage() {
    const moment = currentMoment();
    const draft = draftFor(moment);
    const stage = document.getElementById('studio-stage');
    if (stage) stage.innerHTML = canvas(moment, draft);
    const format = document.getElementById('stage-format');
    if (format) format.textContent = formatName(draft.format);
    const trace = document.getElementById('trace-status');
    if (trace) trace.textContent = draft.trace ? 'Manual trace' : 'No trace applied';
  }

  function refreshTimeline() {
    const moment = currentMoment();
    const time = document.getElementById('current-time');
    const scrub = document.querySelector('[data-input="scrub"]');
    const playhead = document.getElementById('filmstrip-playhead');
    if (time) time.textContent = `${state.time.toFixed(1)}s`;
    if (scrub) scrub.value = state.time;
    if (playhead) playhead.style.left = `${state.time / moment.duration * 100}%`;
  }

  function openDialog(html) {
    stopPlayback();
    previousDialogFocus = document.activeElement;
    dialog.innerHTML = html;
    dialog.showModal();
  }

  const dialogTop = text => `<div class="dialog-topline"><span class="eyebrow">${text}</span><button class="icon-button" data-action="close-dialog" aria-label="Close dialog">${icon('close')}</button></div>`;

  function importDialog() {
    state.importSession = state.session;
    openDialog(`${dialogTop('Add to your session')}<h2 id="dialog-title">Bring the afternoon in.</h2><p class="dialog-description">One recording, or the whole session. Start with a fictional sample to explore the flow.</p><div class="import-choices" role="group" aria-label="Choose a sample recording">${[['range','Range recording','06:18 · Landscape'],['course','Course recording','01:42 · Landscape']].map(([type,title,description]) => `<button class="import-choice ${state.importType === type ? 'active' : ''}" data-action="import-choice" data-type="${type}" aria-pressed="${state.importType === type}"><img src="${photo(type)}" alt=""><strong>${title}</strong><small>${description}</small></button>`).join('')}</div><div class="dialog-field"><label for="import-session">Add to session</label><select id="import-session" data-input="import-session">${sessions.map(s => `<option value="${s.id}" ${state.importSession === s.id ? 'selected' : ''}>${s.title}</option>`).join('')}</select></div><p class="dialog-footnote">This design preview uses fictional recordings and moments. It does not upload files or run shot detection.</p><button class="primary dialog-primary" data-action="import-confirm">Add sample recording ${icon('arrow')}</button>`);
  }

  function exportDialog() {
    const moment = currentMoment();
    const draft = draftFor(moment);
    openDialog(`${dialogTop('Export preview')}<h2 id="dialog-title">A shot worth sharing.</h2><p class="dialog-description">${escape(moment.title)}${moment.keeper ? ' Your keeper, ready for its close-up.' : ' All the good bits, in one frame.'}</p><div class="export-stage">${canvas(moment, draft)}</div><dl class="export-facts"><div><dt>Clip</dt><dd>${durationText(draft.end - draft.start)}</dd></div><div><dt>Format</dt><dd>${formatName(draft.format)}</dd></div><div><dt>Overlay</dt><dd>${draft.trace ? 'Manual trace' : 'No trace'}</dd></div></dl><p class="dialog-footnote">Prototype preview only. No video has been encoded, saved or shared. An actual export would retain the full source frame and any Manual trace label.</p><button class="primary dialog-primary" data-action="export-done">Back to my shot ${icon('check')}</button>`);
  }

  function closeDialog() {
    dialog.close();
    if (previousDialogFocus?.isConnected) previousDialogFocus.focus();
  }

  document.addEventListener('click', event => {
    const button = event.target.closest('[data-action]');
    if (!button) return;
    const action = button.dataset.action;
    const id = button.dataset.id;
    const moment = moments.find(m => m.id === id) || currentMoment();
    if (action === 'nav') return navigate(button.dataset.view);
    if (action === 'session') return selectSession(id);
    if (action === 'session-back') { state.detail = false; render(); window.scrollTo({ top: 0, behavior: 'instant' }); return; }
    if (action === 'session-switch') {
      openDialog(`${dialogTop('Your recordings')}<h2 id="dialog-title">Choose a session.</h2><div class="home-older">${sessions.map(s => `<button class="old-session" style="display:flex;align-items:center;gap:14px;width:100%;text-align:left;padding:14px 0;border-bottom:1px solid var(--rule)" data-action="dialog-session" data-id="${s.id}"><img style="width:75px;height:60px;object-fit:cover;border-radius:3px" src="${photo(s.image)}" alt=""><span><strong style="display:block;font-size:13px">${s.title}</strong><small style="display:block;font-size:10px;color:var(--muted);margin-top:5px">${s.date}</small></span></button>`).join('')}</div>`); return;
    }
    if (action === 'dialog-session') { closeDialog(); selectSession(id); return; }
    if (action === 'select') { state.selected = id; state.detail = true; if (window.matchMedia('(max-width:679px)').matches) openStudio(id); else render(); return; }
    if (action === 'studio') return openStudio(id);
    if (action === 'studio-back') { stopPlayback(); state.view = state.returnView; state.detail = true; render(); window.scrollTo({ top: 0, behavior: 'instant' }); return; }
    if (action === 'recording') { state.detail = true; state.recording = button.dataset.recording; const visible = filteredMoments(); if (visible.length) state.selected = visible[0].id; render(); return; }
    if (action === 'filter') { state.detail = true; state.filter = button.dataset.filter; const visible = filteredMoments(); if (visible.length) state.selected = visible[0].id; render(); return; }
    if (action === 'clear-filters') { state.filter = 'all'; state.recording = 'all'; render(); return; }
    if (action === 'shots-filter') { state.shotsFilter = button.dataset.filter; render(); return; }
    if (action === 'keeper') {
      moment.keeper = !moment.keeper;
      if (moment.keeper) { moment.saved = true; moment.skipped = false; }
      render(); toast(moment.keeper ? 'Saved to Shots and added to Keepers.' : 'Removed from Keepers. Your shot is still saved.'); return;
    }
    if (action === 'save-shot') {
      if (moment.saved) { toast('This shot is already saved. Its original remains intact.'); return; }
      moment.saved = true; moment.skipped = false; render(); toast('Saved to Shots. Your original recording is untouched.'); return;
    }
    if (action === 'skip') {
      moment.skipped = !moment.skipped;
      if (moment.skipped) { const visible = filteredMoments(); if (visible.length) state.selected = visible[0].id; }
      render(); toast(moment.skipped ? 'Moved to Skipped. You can restore it at any time.' : 'Restored to your contact sheet.'); return;
    }
    if (action === 'step') { state.detail = true; const list = filteredMoments(); if (!list.length) return; const index = list.findIndex(m => m.id === state.selected); state.selected = list[(index + Number(button.dataset.direction) + list.length) % list.length].id; render(); return; }
    if (action === 'tool') {
      state.tool = button.dataset.tool;
      document.querySelectorAll('[data-action="tool"]').forEach(tab => { const selected = tab.dataset.tool === state.tool; tab.classList.toggle('active', selected); tab.setAttribute('aria-selected', selected); tab.tabIndex = selected ? 0 : -1; });
      const panel = document.getElementById('tool-content'); panel.innerHTML = toolPanel(); panel.setAttribute('aria-labelledby', `tab-${state.tool}`); return;
    }
    if (action === 'trace-toggle') { const draft = draftFor(moment); draft.trace = !draft.trace; button.setAttribute('aria-checked', draft.trace); refreshStage(); toast(draft.trace ? 'Manual sample trace shown. Its label stays with the export.' : 'Manual trace hidden.'); return; }
    if (action === 'trace-colour') { draftFor(moment).colour = button.dataset.colour; document.querySelectorAll('[data-action="trace-colour"]').forEach(swatch => { const active = swatch.dataset.colour === button.dataset.colour; swatch.classList.toggle('active', active); swatch.setAttribute('aria-pressed', active); }); refreshStage(); return; }
    if (action === 'format') { draftFor(moment).format = button.dataset.format; document.querySelectorAll('[data-action="format"]').forEach(option => { const active = option.dataset.format === button.dataset.format; option.classList.toggle('active', active); option.setAttribute('aria-pressed', active); }); refreshStage(); toast(`${formatName(button.dataset.format)} canvas. The complete source stays in frame.`); return; }
    if (action === 'reset-trim') { const draft = draftFor(moment); draft.start = 0; draft.end = moment.duration; document.getElementById('tool-content').innerHTML = toolPanel(); toast('Full moment restored.'); return; }
    if (action === 'play') {
      if (state.playing) { stopPlayback(); button.innerHTML = icon('play'); button.setAttribute('aria-label','Play sample timeline'); return; }
      state.playing = true; button.innerHTML = icon('pause'); button.setAttribute('aria-label','Pause sample timeline'); toast('Sample timeline playing. The preview uses a still image.');
      playbackTimer = setInterval(() => { const draft = draftFor(currentMoment()); state.time = state.time >= draft.end ? draft.start : Math.min(draft.end, state.time + .1); refreshTimeline(); }, 100); return;
    }
    if (action === 'frame') { stopPlayback(); state.time = Math.max(0, Math.min(moment.duration, state.time + Number(button.dataset.direction) * .1)); refreshTimeline(); const play = document.querySelector('[data-action="play"]'); if (play) { play.innerHTML = icon('play'); play.setAttribute('aria-label','Play sample timeline'); } return; }
    if (action === 'import') return importDialog();
    if (action === 'import-choice') { state.importType = button.dataset.type; document.querySelectorAll('.import-choice').forEach(choice => { const selected = choice.dataset.type === state.importType; choice.classList.toggle('active', selected); choice.setAttribute('aria-pressed', selected); }); return; }
    if (action === 'import-confirm') {
      const session = sessionById(state.importSession); session.recordings += 1; importCount += 1;
      const priorDuration = session.sourceDuration.split(':').reduce((total, part) => total * 60 + Number(part), 0);
      session.sourceDuration = seconds(priorDuration + (state.importType === 'range' ? 378 : 102));
      const ids = [`sample-${importCount}-1`, `sample-${importCount}-2`];
      moments.push({ id: ids[0], session: session.id, title: 'A new favourite?', image: state.importType, recording: session.recordings, start: 16, duration: 8, saved: false, keeper: false, skipped: false, position: '40% 50%' }, { id: ids[1], session: session.id, title: 'One more for the roll', image: state.importType, recording: session.recordings, start: 48, duration: 7, saved: false, keeper: false, skipped: false, position: '60% 50%' });
      closeDialog(); selectSession(session.id); state.recording = String(session.recordings); state.selected = ids[0]; render(); toast('Sample recording added with two fictional moments.'); return;
    }
    if (action === 'export') return exportDialog();
    if (action === 'export-done') { closeDialog(); toast('Export preview reviewed. Your edit stays in this preview.'); return; }
    if (action === 'close-dialog') return closeDialog();
    if (action === 'about') {
      openDialog(`${dialogTop('Ronde / Cutroom')}<h2 id="dialog-title">Your game.<br>Your edit.</h2><div class="about-copy"><p>This is an interactive design exploration with <strong>fictional sessions, people and media</strong>.</p><br><p>Try opening a session, saving a moment, adding a Keeper, and editing a shot. Sample annotations are always labelled Manual trace.</p><br><p>No files are uploaded, no shots are detected, and no video is encoded or shared. Your choices last while this preview stays open.</p></div><button class="primary dialog-primary" data-action="close-dialog">Back to the session ${icon('arrow')}</button>`);
    }
  });

  document.addEventListener('input', event => {
    const input = event.target;
    if (!input.dataset.input) return;
    const kind = input.dataset.input;
    if (kind === 'import-session') { state.importSession = input.value; return; }
    const moment = currentMoment();
    const draft = draftFor(moment);
    if (kind === 'scrub') { stopPlayback(); state.time = Number(input.value); refreshTimeline(); const play = document.querySelector('[data-action="play"]'); if (play) { play.innerHTML = icon('play'); play.setAttribute('aria-label','Play sample timeline'); } return; }
    if (kind === 'trim-start') { draft.start = Math.min(Number(input.value), draft.end - .5); input.value = draft.start; }
    if (kind === 'trim-end') { draft.end = Math.max(Number(input.value), draft.start + .5); input.value = draft.end; }
    if (kind.startsWith('trim-')) {
      document.getElementById('trim-start-value').textContent = `${draft.start.toFixed(1)}s`;
      document.getElementById('trim-end-value').textContent = `${draft.end.toFixed(1)}s`;
      document.getElementById('trim-duration').textContent = durationText(draft.end - draft.start);
      state.time = Math.max(draft.start, Math.min(draft.end, state.time)); refreshTimeline();
      const strip = document.querySelector('.filmstrip'); strip.style.borderLeftWidth = `${Math.max(2, draft.start / moment.duration * 25)}px`; strip.style.borderRightWidth = `${Math.max(2, (moment.duration - draft.end) / moment.duration * 25)}px`;
    }
  });

  document.addEventListener('keydown', event => {
    if (event.target.matches('[role="tab"]') && ['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) {
      event.preventDefault();
      const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
      const index = tabs.indexOf(event.target);
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
      tabs[next].click(); tabs[next].focus();
    }
  });

  dialog.addEventListener('click', event => { if (event.target === dialog) { const rect = dialog.getBoundingClientRect(); if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) closeDialog(); } });
  window.addEventListener('message', event => { if (event.origin !== window.location.origin || event.source !== window.parent) return; if (event.data?.type === 'ronde:navigate' && ['sessions','shots','studio'].includes(event.data.view)) navigate(event.data.view); });
  document.addEventListener('visibilitychange', () => { if (document.hidden) stopPlayback(); });
  render();
})();
