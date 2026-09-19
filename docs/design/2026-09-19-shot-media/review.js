(() => {
  'use strict';
  const directions = {
    clubhouse: { name: 'Clubhouse', number: '01', title: 'A place for the good ones.', description: 'The selected foundation, now with a recording Studio. Bookmark a swing, adjust the room either side, and create a list of shots to trim, trace and share.', tradeoff: 'Warmth and a clear editing flow. This pass refines the structure; the visual system will keep developing.' },
    cutroom: { name: 'Cutroom', number: '02', title: 'Turn a recording into a shortlist.', description: 'A precise cobalt workspace built around source recordings and contact sheets. See the candidates together, keep the best, and carry them straight into the editor.', tradeoff: 'The strongest workflow for lots of footage; more functional than sentimental.' },
    fieldwork: { name: 'Fieldwork', number: '03', title: 'A small decision with a big payoff.', description: 'Expressive type, warm sand and a flash of vermilion. Review one possible shot at a time, with a clear choice to keep moving or keep the moment.', tradeoff: 'The quickest rhythm on a phone; comparing several shots needs an extra step.' }
  };
  const devices = {
    phone: { name: 'iPhone', width: 393, height: 790, border: 6 },
    duo: { name: 'Duo expanded', width: 760, height: 740, border: 5 },
    ipad: { name: 'iPad', width: 1120, height: 790, border: 0 }
  };
  const query = new URLSearchParams(location.search);
  const state = { direction: directions[query.get('direction')] ? query.get('direction') : 'clubhouse', device: devices[query.get('device')] ? query.get('device') : (window.innerWidth < 700 ? 'phone' : 'ipad'), view: ['sessions', 'shots', 'studio'].includes(query.get('view')) ? query.get('view') : 'sessions', panel: query.get('panel') === 'structure' ? 'structure' : 'concepts' };
  const frame = document.getElementById('concept-frame');
  const frameShell = document.getElementById('frame-shell');
  const frameFit = document.getElementById('frame-fit');
  const canvas = document.getElementById('preview-canvas');
  const directionButtons = [...document.querySelectorAll('[data-direction]')];
  const deviceButtons = [...document.querySelectorAll('[data-device]')];
  const viewButtons = [...document.querySelectorAll('[data-view]')];

  function saveLocation() {
    const url = new URL(location.href);
    for (const [key, value] of Object.entries(state)) url.searchParams.set(key, value);
    history.replaceState(null, '', url);
  }
  function sendView() {
    if (!frame.contentWindow) return;
    // The review is served locally; file URLs cannot offer a shared origin.
    if (location.origin !== 'null') frame.contentWindow.postMessage({ type: 'ronde:navigate', view: state.view }, location.origin);
  }
  function resizePreview() {
    if (canvas.hidden || !canvas.clientWidth) return;
    const config = devices[state.device];
    const style = getComputedStyle(canvas);
    const available = canvas.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    const outerWidth = config.width + config.border * 2;
    const outerHeight = config.height + config.border * 2;
    const scale = Math.min(1, available / outerWidth);
    frame.width = config.width;
    frame.height = config.height;
    frame.style.width = `${config.width}px`;
    frame.style.height = `${config.height}px`;
    frameShell.style.width = `${outerWidth}px`;
    frameShell.style.height = `${outerHeight}px`;
    frameShell.style.transform = `scale(${scale})`;
    frameShell.dataset.device = state.device;
    frameFit.style.width = `${outerWidth * scale}px`;
    frameFit.style.height = `${outerHeight * scale}px`;
    document.getElementById('viewport-label').textContent = `${config.name} · ${config.width}px illustrative viewport`;
    document.getElementById('scale-label').textContent = scale < .995 ? `Fit to space · ${Math.round(scale * 100)}%` : 'Actual CSS size · 100%';
  }
  function selectDevice(device) {
    state.device = device;
    for (const button of deviceButtons) button.setAttribute('aria-pressed', String(button.dataset.device === device));
    resizePreview();
    saveLocation();
  }
  function selectView(view) {
    state.view = view;
    for (const button of viewButtons) button.setAttribute('aria-pressed', String(button.dataset.view === view));
    sendView();
    saveLocation();
  }
  function selectDirection(direction) {
    const config = directions[direction];
    const changed = frame.getAttribute('src') !== `${direction}.html`;
    state.direction = direction;
    for (const button of directionButtons) {
      const selected = button.dataset.direction === direction;
      button.setAttribute('aria-selected', String(selected));
      button.tabIndex = selected ? 0 : -1;
    }
    document.getElementById('concept-panel').setAttribute('aria-labelledby', `tab-${direction}`);
    document.getElementById('caption-label').textContent = `${config.number} / ${config.name.toUpperCase()}`;
    document.getElementById('caption-title').textContent = config.title;
    document.getElementById('caption-description').textContent = config.description;
    document.getElementById('caption-tradeoff').textContent = config.tradeoff;
    document.getElementById('standalone-link').href = `${direction}.html`;
    frame.title = `${config.name} interactive Ronde concept`;
    if (changed) frame.src = `${direction}.html`;
    saveLocation();
  }
  function selectPanel(panel) {
    state.panel = panel;
    document.getElementById('concepts-panel').hidden = panel !== 'concepts';
    document.getElementById('structure-panel').hidden = panel !== 'structure';
    for (const button of document.querySelectorAll('[data-panel]')) button.setAttribute('aria-pressed', String(button.dataset.panel === panel));
    if (panel === 'concepts') requestAnimationFrame(resizePreview);
    saveLocation();
  }
  directionButtons.forEach((button, index) => {
    button.addEventListener('click', () => selectDirection(button.dataset.direction));
    button.addEventListener('keydown', event => {
      let next = index;
      if (event.key === 'ArrowRight') next = (index + 1) % directionButtons.length;
      else if (event.key === 'ArrowLeft') next = (index - 1 + directionButtons.length) % directionButtons.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = directionButtons.length - 1;
      else return;
      event.preventDefault();
      directionButtons[next].focus();
      selectDirection(directionButtons[next].dataset.direction);
    });
  });
  deviceButtons.forEach(button => button.addEventListener('click', () => selectDevice(button.dataset.device)));
  viewButtons.forEach(button => button.addEventListener('click', () => selectView(button.dataset.view)));
  document.querySelectorAll('[data-panel]').forEach(button => button.addEventListener('click', () => selectPanel(button.dataset.panel)));
  frame.addEventListener('load', sendView);
  window.addEventListener('resize', resizePreview);
  if ('ResizeObserver' in window) new ResizeObserver(resizePreview).observe(canvas);
  selectDirection(state.direction);
  selectDevice(state.device);
  selectView(state.view);
  selectPanel(state.panel);
})();
