const tabs = [...document.querySelectorAll('.concept-tab')];
const concepts = [...document.querySelectorAll('.concept')];

function activateConcept(id) {
  tabs.forEach((tab) => {
    const active = tab.dataset.target === id;
    tab.classList.toggle('is-active', active);
    tab.setAttribute('aria-pressed', String(active));
  });

  concepts.forEach((concept) => {
    const active = concept.dataset.concept === id;
    concept.classList.toggle('is-active', active);
    concept.hidden = !active;
  });

  const url = new URL(window.location.href);
  url.searchParams.set('concept', id);
  window.history.replaceState({}, '', url);
}

tabs.forEach((tab) => tab.addEventListener('click', () => activateConcept(tab.dataset.target)));

const requested = new URL(window.location.href).searchParams.get('concept');
if (tabs.some((tab) => tab.dataset.target === requested)) activateConcept(requested);

// Creation is a labelled navigation action. It does not float over content or
// compete with the system tab bar.
document.querySelectorAll('.floating-add').forEach((control) => control.remove());

document.querySelectorAll('.concept .phone:not(.phone-login) .app-header').forEach((header) => {
  const existingAction = [...header.children].find((child) => child.matches('button'));
  const actions = document.createElement('div');
  actions.className = 'toolbar-actions';

  const importAction = document.createElement('button');
  importAction.className = 'import-action glass';
  importAction.textContent = 'Import';
  importAction.setAttribute('aria-label', 'Import footage');
  actions.append(importAction);

  if (existingAction) actions.append(existingAction);
  header.append(actions);
});

const workflowContent = {
  caddie: {
    title: 'The review stays video-first.',
    lede: 'Tap any media tile to open playback. Editing is a deliberate mode below the video, while provenance stays visible without becoming technical noise.',
    evidence: '8 observed points · estimated flight',
    detail: 'A calm control sheet keeps trim, trace and details one tap away.',
    location: 'Moore Park Golf · Sydney'
  },
  flightline: {
    title: 'Evidence is visible, never theatrical.',
    lede: 'Playback exposes the observed and estimated segments clearly. The inspector adds source time and confidence detail without claiming measured distance.',
    evidence: 'Observed 0.18 s · 8 points · 84%',
    detail: 'The evidence inspector explains why this trace is displayable.',
    location: 'Moore Park · Fixed camera'
  },
  journal: {
    title: 'A shot remains attached to its story.',
    lede: 'The same precise review interaction keeps the session, optional place and personal note close at hand without obscuring the footage.',
    evidence: 'Observed launch · estimated flight',
    detail: 'Edit the media, then return to the place and session it belongs to.',
    location: 'Moore Park Golf · 30 August'
  }
};

function icon(id, className = '') {
  return `<svg class="${className}" aria-hidden="true"><use href="#${id}"/></svg>`;
}

function workflowMarkup(conceptId, content) {
  const tracerClass = conceptId === 'flightline' ? 'tracer-cyan' : conceptId === 'journal' ? 'tracer-cream' : 'tracer-gold';
  return `
    <section class="media-workflow" id="${conceptId}-media" aria-label="Individual media review and editing">
      <div class="workflow-intro">
        <div>
          <p class="eyebrow">Individual media · interaction sequence</p>
          <h3>${content.title}</h3>
        </div>
        <p>${content.lede}</p>
      </div>

      <div class="workflow-board">
        <article class="phone review-phone">
          <p class="screen-label">01 · Review</p>
          <div class="device-shell">
            <div class="phone-screen media-review-screen">
              <div class="statusbar"><span>9:41</span><span>● ◒ ▰</span></div>
              <div class="review-video media-day">
                <div class="review-topbar">
                  <button class="glass-icon" aria-label="Back">${icon('i-back')}</button>
                  <div class="review-top-actions">
                    <button class="glass-icon is-saved" aria-label="Saved">${icon('i-heart')}</button>
                    <button class="glass-icon" aria-label="More options">${icon('i-ellipsis')}</button>
                  </div>
                </div>
                <div class="golfer" aria-hidden="true"><i></i><b></b><em></em></div>
                <svg class="tracer ${tracerClass}" viewBox="0 0 320 360" aria-hidden="true">
                  <path class="observed" d="M82 292C104 219 130 153 158 116"/>
                  <path class="estimated" d="M158 116C207 72 260 105 292 177"/>
                </svg>
                <div class="review-provenance"><span class="provenance-dot"></span>${content.evidence}</div>
                <button class="review-play" aria-label="Pause video">${icon('i-pause')}</button>
                <div class="review-scrubber">
                  <span>0:04</span><div class="scrub-track"><i style="--progress:42%"></i><b style="--at:42%"></b></div><span>0:12</span>
                </div>
              </div>
              <div class="review-sheet">
                <div class="sheet-grabber"></div>
                <div class="review-title-row"><div><small>ONE SHOT · 7-IRON</small><h4>Moore Park, yesterday</h4></div><button aria-label="Share">${icon('i-share')}</button></div>
                <p class="review-summary">${content.detail}</p>
                <div class="review-tool-row">
                  <button>${icon('i-scissors')}<span>Trim</span></button>
                  <button data-jump-editor>${icon('i-pencil')}<span>Edit trace</span></button>
                  <button>${icon('i-info')}<span>Details</span></button>
                </div>
              </div>
              <div class="home-indicator"></div>
            </div>
          </div>
        </article>

        <article class="phone trim-phone">
          <p class="screen-label">02 · Trim & details</p>
          <div class="device-shell">
            <div class="phone-screen editor-screen">
              <div class="statusbar"><span>9:41</span><span>● ◒ ▰</span></div>
              <header class="editor-navbar"><button>Cancel</button><strong>Edit review</strong><button class="done-action">Done</button></header>
              <div class="editor-preview media-day">
                <div class="golfer" aria-hidden="true"><i></i><b></b><em></em></div>
                <svg class="tracer ${tracerClass}" viewBox="0 0 320 230" aria-hidden="true"><path class="observed" d="M83 193C107 136 134 100 160 79"/><path class="estimated" d="M160 79C208 48 260 69 291 121"/></svg>
                <button class="play-button" aria-label="Play">${icon('i-play')}</button>
              </div>
              <div class="edit-mode-switch" role="tablist" aria-label="Edit mode"><button class="is-active" role="tab">Trim</button><button role="tab">Details</button></div>
              <div class="timeline-editor">
                <div class="timeline-labels"><span>Impact −5 s</span><strong>0:10 clip</strong><span>+5 s</span></div>
                <div class="filmstrip"><i></i><i></i><i></i><i></i><i></i><i></i><b class="trim-handle start"></b><b class="trim-handle end"></b><em></em></div>
                <div class="source-time"><span>00:18.40</span><span>00:28.40</span></div>
              </div>
              <div class="detail-fields">
                <button><span><small>PLACE</small><strong>${content.location}</strong></span>${icon('i-chevron')}</button>
                <button><span><small>CLUB</small><strong>7-iron</strong></span>${icon('i-chevron')}</button>
                <button><span><small>NOTE</small><strong>Add a note</strong></span>${icon('i-chevron')}</button>
              </div>
              <div class="home-indicator"></div>
            </div>
          </div>
        </article>

        <article class="phone trace-edit-phone">
          <p class="screen-label">03 · Edit trace</p>
          <div class="device-shell">
            <div class="phone-screen trace-editor-screen">
              <div class="statusbar"><span>9:41</span><span>● ◒ ▰</span></div>
              <header class="trace-editor-navbar"><button class="glass-icon" aria-label="Close">${icon('i-back')}</button><div><small>MANUAL TRACE</small><strong>Place the flight path</strong></div><button class="glass-text save-trace">Save</button></header>
              <div class="trace-edit-stage media-day">
                <div class="golfer" aria-hidden="true"><i></i><b></b><em></em></div>
                <svg class="manual-trace" viewBox="0 0 320 380" aria-hidden="true"><path d="M82 313C108 217 176 92 285 181"/></svg>
                <button class="trace-point impact is-selected" data-point="Impact" style="--x:25%;--y:82%"><i></i><span>Impact</span></button>
                <button class="trace-point apex" data-point="Apex" style="--x:55%;--y:25%"><i></i><span>Apex</span></button>
                <button class="trace-point landing" data-point="Landing" style="--x:89%;--y:47%"><i></i><span>Landing</span></button>
                <div class="manual-badge">Manual trace · user authored</div>
              </div>
              <div class="trace-control-sheet">
                <div class="sheet-grabber"></div>
                <div class="selected-point"><span>SELECTED POINT</span><strong data-selected-point>Impact</strong><p>Drag the handle to the ball at impact.</p></div>
                <div class="editor-actions">
                  <button>${icon('i-undo')}<span>Undo</span></button>
                  <button>${icon('i-frame')}<span>Fit video</span></button>
                  <button class="destructive"><span>Reset path</span></button>
                </div>
                <p class="honesty-note">Editing replaces the automatic presentation with a clearly labelled manual path. Observed evidence is never moved.</p>
              </div>
              <div class="home-indicator"></div>
            </div>
          </div>
        </article>
      </div>
    </section>`;
}

concepts.forEach((concept) => {
  const id = concept.dataset.concept;
  concept.insertAdjacentHTML('beforeend', workflowMarkup(id, workflowContent[id]));
});

document.querySelectorAll('[data-jump-editor]').forEach((button) => {
  button.addEventListener('click', () => {
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    button.closest('.media-workflow').querySelector('.trace-edit-phone').scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', inline: 'center', block: 'nearest' });
  });
});

document.querySelectorAll('.trace-point').forEach((point) => {
  point.addEventListener('click', () => {
    const editor = point.closest('.trace-edit-phone');
    editor.querySelectorAll('.trace-point').forEach((candidate) => candidate.classList.remove('is-selected'));
    point.classList.add('is-selected');
    editor.querySelector('[data-selected-point]').textContent = point.dataset.point;
  });
});
