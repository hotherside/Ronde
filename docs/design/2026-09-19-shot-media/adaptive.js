(() => {
  'use strict';
  const poses = {
    outer: { number: '01', label: 'OUTER DISPLAY / COMPACT', title: 'One shot.<br>Everything within reach.', description: 'Focus on the selected shot. The session remains one navigation step away, while the actions sit along the outer edge.', pattern: 'The outer screen uses vertical controls to preserve content height. Safe areas account for the camera, system status and shared bar region.', interpretation: 'Show a focused studio with the same favourite, trace, format and export actions. Folding closed does not discard the editing state.', source: 'https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo' },
    landscape: { number: '02', label: 'INNER DISPLAY / LANDSCAPE', title: 'Room for the shot<br>and its context.', description: 'The session stays beside the selected shot. Studio actions move to the outer edge, preserving vertical space for media.', pattern: 'Outer display and inner landscape use vertical system bars. In a split view, the detail column participates; the collection keeps its own controls.', interpretation: 'Keep the library beside the preview, with edit actions near the media they affect. Selection and draft choices survive the transition.', source: 'https://developer.apple.com/videos/play/tech-talks/111462/' },
    portrait: { number: '03', label: 'INNER DISPLAY / PORTRAIT', title: 'More height.<br>A familiar arrangement.', description: 'Media, timeline and actions stack naturally. A wider player makes the source easier to review, while the controls return to a horizontal bar.', pattern: 'The inner display in portrait retains horizontal bars. The same controls and content remain available as the device changes pose.', interpretation: 'Use the extra height for the shot and its timeline. Keep a compact path back to the session, instead of forcing narrow side-by-side panels.', source: 'https://developer.apple.com/videos/play/tech-talks/111466/' },
    tabletop: { number: '04', label: 'INNER DISPLAY / PARTLY FOLDED', title: 'The preview up top.<br>Your hands down here.', description: 'Keep the media clearly visible above the fold. Put the timeline and editing actions on the stable lower surface.', pattern: 'Apple’s tabletop guidance places visible media above and interactive controls below. Reserved regions identify the active fold; the gap is unnecessary when flat.', interpretation: 'The player and controls become two related regions. Keep the trim handles clear of the crease, with the same actions available in every pose.', source: 'https://developer.apple.com/videos/play/tech-talks/111463/' }
  };
  const device = document.getElementById('study-device');
  const favourite = document.getElementById('study-favourite');
  const traceButton = document.getElementById('study-trace-toggle');
  const feedback = document.getElementById('study-feedback');
  const scrubber = document.getElementById('study-scrubber');
  const state = { favourite: true, trace: false, format: 'Original', position: 4 };

  document.querySelectorAll('[data-pose]').forEach(button => {
    if (button.tagName !== 'BUTTON') return;
    button.addEventListener('click', () => {
      const pose = button.dataset.pose;
      const config = poses[pose];
      device.dataset.pose = pose;
      document.querySelectorAll('button[data-pose]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
      document.getElementById('pose-label').textContent = config.label;
      document.getElementById('pose-index').textContent = config.number;
      document.getElementById('pose-title').innerHTML = config.title;
      document.getElementById('pose-description').textContent = config.description;
      document.getElementById('apple-pattern').textContent = config.pattern;
      document.getElementById('ronde-interpretation').textContent = config.interpretation;
      document.getElementById('pose-source').href = config.source;
      feedback.textContent = `Still Shot 04 · ${state.favourite ? 'Keeper' : 'Not favourited'} · ${state.format} format · ${state.position}s.`;
    });
  });
  favourite.addEventListener('click', () => {
    state.favourite = !state.favourite;
    favourite.setAttribute('aria-pressed', String(state.favourite));
    favourite.setAttribute('aria-label', state.favourite ? 'Remove from keepers' : 'Add to keepers');
    document.getElementById('study-keeper').textContent = state.favourite ? '☆ Keeper' : 'Confirmed shot';
    feedback.textContent = state.favourite ? 'Added to keepers. The original stays where it is.' : 'Removed from keepers. The shot and original are preserved.';
  });
  traceButton.addEventListener('click', () => {
    state.trace = !state.trace;
    traceButton.setAttribute('aria-pressed', String(state.trace));
    traceButton.setAttribute('aria-label', state.trace ? 'Hide illustrative manual trace' : 'Show illustrative manual trace');
    document.getElementById('study-trace').classList.toggle('visible', state.trace);
    document.getElementById('trace-caption').classList.toggle('visible', state.trace);
    feedback.textContent = state.trace ? 'Illustrative manual trace shown. This line is not tracking evidence.' : 'Illustrative trace hidden. The shot is still ready to edit.';
  });
  document.getElementById('study-format').addEventListener('click', () => {
    const formats = ['Original', '9:16', '1:1'];
    state.format = formats[(formats.indexOf(state.format) + 1) % formats.length];
    document.getElementById('format-label').textContent = state.format === 'Original' ? 'Fit' : state.format;
    document.querySelector('.study-edit-foot span:last-child').textContent = `${state.format === 'Original' ? 'Original aspect' : `${state.format} fit`} · 8 seconds`;
    feedback.textContent = `${state.format} export selected. This layout study keeps the full sample frame visible.`;
  });
  scrubber.addEventListener('input', () => {
    state.position = Number(scrubber.value);
    scrubber.setAttribute('aria-valuetext', `${state.position} seconds of 8 seconds`);
    document.getElementById('study-time').textContent = `00:0${state.position} / 00:08`;
    document.querySelector('.study-filmstrip > span').style.left = `${state.position / 8 * 100}%`;
    feedback.textContent = `Position set to ${state.position}s. The image is a static layout sample.`;
  });
  document.getElementById('study-export').addEventListener('click', () => {
    feedback.textContent = `Export preview: Shot 04 · ${state.format} · 8 seconds${state.trace ? ' · labelled manual trace' : ''}. No file is created in this study.`;
  });
})();
