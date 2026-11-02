// Set these to the real links before publishing.
const DOWNLOAD_URL = '#download'; // a .dmg or a store page
const DONATE_URL = '#donate';     // GitHub Sponsors, Buy Me a Coffee, Ko-fi, …
const GITHUB_URL = '#github';     // the repository

const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

document.querySelectorAll('[data-download]').forEach((a) => {
  a.href = DOWNLOAD_URL;
  if (/\.(dmg|zip|pkg)$/i.test(DOWNLOAD_URL)) a.setAttribute('download', '');
});
// Donate and GitHub open in a new tab once they point somewhere real.
[['[data-donate]', DONATE_URL], ['[data-github]', GITHUB_URL]].forEach(([sel, url]) => {
  document.querySelectorAll(sel).forEach((a) => {
    a.href = url;
    if (/^https?:/i.test(url)) { a.target = '_blank'; a.rel = 'noopener'; }
  });
});

// The tour video: plays with sound while on screen, pauses off screen and
// under reduced motion. Browsers refuse sound before the visitor has touched
// the page, so then it plays muted and the sound comes on with the first
// click or key press. Without assets/tour.mp4 the poster stays and the
// controls stay hidden.
(() => {
  const video = document.getElementById('tour-video');
  const frame = document.getElementById('hero-window');
  const sound = document.getElementById('sound');
  if (!video || !frame) return;
  const toggle = frame.querySelector('[data-loop-toggle]');
  const s = { ready: false, seen: false, held: reduceMotion.matches, wantSound: true };

  const setMuted = (muted) => {
    video.muted = muted;
    sound.setAttribute('aria-pressed', String(!muted));
    sound.querySelector('.sound-label').textContent = muted ? 'Turn sound on' : 'Turn sound off';
  };

  // Sound was refused: unmute on the first gesture anywhere, unless that
  // gesture is on the sound button, which decides for itself.
  const gestures = ['pointerdown', 'keydown'];
  const unmuteOnGesture = (e) => {
    gestures.forEach((t) => document.removeEventListener(t, unmuteOnGesture, true));
    if (e.target.closest && e.target.closest('#sound')) return;
    if (s.wantSound) setMuted(false);
  };
  const armUnmute = () => gestures.forEach((t) => document.addEventListener(t, unmuteOnGesture, true));

  const sync = () => {
    const run = s.ready && s.seen && !s.held;
    toggle.textContent = s.held ? 'Play' : 'Pause';
    if (!run) { video.pause(); return; }
    video.play().catch((err) => {
      if (err.name !== 'NotAllowedError' || video.muted) return;
      setMuted(true);
      armUnmute();
      video.play().catch(() => {});
    });
  };
  const fail = () => { s.ready = false; toggle.hidden = true; sound.hidden = true; frame.classList.add('no-video'); };
  video.addEventListener('error', fail);
  if (video.error || video.networkState === 3) fail();
  const ready = () => {
    if (s.ready) return;
    s.ready = true; toggle.hidden = false; sound.hidden = false; frame.classList.remove('no-video'); sync();
  };
  video.addEventListener('loadedmetadata', ready);
  if (video.readyState >= 1) ready();

  toggle.addEventListener('click', () => { s.held = !s.held; sync(); });
  new IntersectionObserver(([e]) => { s.seen = e.isIntersecting; sync(); }).observe(frame);
  reduceMotion.addEventListener('change', () => { s.held = reduceMotion.matches; sync(); });

  sound.addEventListener('click', () => {
    s.wantSound = video.muted;
    setMuted(!s.wantSound);
  });
  setMuted(false);
})();

// Before and after: the handle and the layers.
(() => {
  const box = document.getElementById('compare');
  const handle = document.getElementById('handle');
  if (!box || !handle) return;

  let value = 50;
  const set = (v) => {
    value = Math.min(100, Math.max(0, v));
    box.style.setProperty('--split', value + '%');
    handle.setAttribute('aria-valuenow', String(Math.round(value)));
    handle.setAttribute('aria-valuetext', Math.round(value) + '% raw');
  };
  const fromPointer = (e) => {
    const r = box.getBoundingClientRect();
    set(((e.clientX - r.left) / r.width) * 100);
  };

  let dragging = false;
  box.addEventListener('pointerdown', (e) => { dragging = true; fromPointer(e); handle.focus({ preventScroll: true }); });
  box.addEventListener('pointermove', (e) => { if (dragging) fromPointer(e); });
  const stop = () => { dragging = false; };
  box.addEventListener('pointerup', stop);
  box.addEventListener('pointercancel', stop);

  handle.addEventListener('keydown', (e) => {
    const step = e.shiftKey ? 10 : 2;
    const keys = {
      ArrowLeft: value - step, ArrowDown: value - step,
      ArrowRight: value + step, ArrowUp: value + step,
      PageDown: value - 10, PageUp: value + 10, Home: 0, End: 100,
    };
    if (e.key in keys) { e.preventDefault(); set(keys[e.key]); }
  });

  const pad = document.getElementById('pad');
  const round = document.getElementById('round');
  const padOut = document.getElementById('pad-out');
  const roundOut = document.getElementById('round-out');
  const cam = document.getElementById('cam');
  const zoom = document.getElementById('zoom');
  const fill = (input) => input.style.setProperty('--fill', ((input.value - input.min) / (input.max - input.min)) * 100 + '%');
  const update = () => {
    box.style.setProperty('--pad', pad.value);
    box.style.setProperty('--round', round.value);
    fill(pad); fill(round);
    padOut.innerHTML = pad.value + '<span class="u">&thinsp;%</span>';
    roundOut.innerHTML = round.value + '<span class="u">&thinsp;px</span>';
    const bg = document.querySelector('input[name="bg"]:checked');
    box.style.setProperty('--bg-canvas', 'var(--bg-' + (bg ? bg.value : 'ocean') + ')');
    box.classList.toggle('no-cam', !cam.checked);
    box.classList.toggle('zoomed', zoom.checked);
  };
  const controls = document.getElementById('controls');
  controls.addEventListener('input', update);
  controls.addEventListener('submit', (e) => e.preventDefault());
  update();
})();

// The map: the step in the middle of the screen picks the screen and its leader.
(() => {
  const steps = [...document.querySelectorAll('.step')];
  const shots = new Map([...document.querySelectorAll('.tv')].map((el) => [el.dataset.for, el]));
  if (!steps.length || !('IntersectionObserver' in window)) return;

  const tour = document.getElementById('tour');
  const warm = new IntersectionObserver((entries) => {
    if (entries.some((e) => e.isIntersecting)) {
      shots.forEach((el) => { el.querySelector('img').loading = 'eager'; });
      warm.disconnect();
    }
  }, { rootMargin: '600px 0px' });
  warm.observe(tour);

  const activate = (step) => {
    steps.forEach((s) => s.classList.toggle('is-active', s === step));
    shots.forEach((el, key) => el.classList.toggle('is-active', key === step.dataset.step));
  };
  activate(steps[0]);

  const io = new IntersectionObserver((entries) => {
    entries.forEach((e) => { if (e.isIntersecting) activate(e.target); });
  }, { rootMargin: '-45% 0px -45% 0px' });
  steps.forEach((s) => io.observe(s));
})();

// Captions switcher: without script both panels show in order.
document.querySelectorAll('[data-switch]').forEach((area) => {
  const tabs = [...area.querySelectorAll('[role="tab"]')];
  const show = (tab, focus) => {
    tabs.forEach((t) => {
      const on = t === tab;
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
      document.getElementById(t.getAttribute('aria-controls')).hidden = !on;
    });
    if (focus) tab.focus();
  };
  tabs.forEach((t, i) => {
    t.addEventListener('click', () => show(t));
    t.addEventListener('keydown', (e) => {
      const d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
      if (d) { e.preventDefault(); show(tabs[(i + d + tabs.length) % tabs.length], true); }
    });
  });
  show(tabs[0]);
});
