import '@fontsource-variable/geist-mono';
import './style.css';
import { tools, steps, shots } from './content.js';

const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const pad = n => String(n).padStart(3, '0');

/* ---------- Content ---------- */
$('#tool-cards').innerHTML = tools.map((t, i) => `
  <li class="card tool" tabindex="0">
    <header class="card-head"><h3>${t.name}</h3><span class="idx">${pad(i + 1)}</span></header>
    <div class="frame"><div class="art" data-art="${t.art}"></div></div>
    <p class="card-foot">${t.line}</p>
  </li>`).join('');

$('#step-list').innerHTML = steps.map(([name, text], i) => `
  <li class="step"><span class="idx">${pad(i + 1)}</span><h3>${name}</h3><p>${text}</p></li>`).join('');

/* ---------- Illustrations ---------- */
const views = new Map();
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
let paused = reduced.matches;
let stage = null;
import('./scenes.js').then(({ createStage }) => {
  stage = createStage($('#stage'));
  if (!stage) { document.body.classList.add('no-webgl'); return; }
  $$('.art').forEach(el => {
    const view = stage.add(el, el.dataset.art, { open: true, progress: 0 });
    if (el.dataset.theme === 'light') view.state.theme = view.state.targetTheme = 1;
    views.set(el, view);
  });
  stage.pause(paused);
  onScroll();
}).catch(() => document.body.classList.add('no-webgl'));

// A tool card turns to paper while you look at it.
$$('.tool').forEach(card => {
  const set = on => {
    card.classList.toggle('lit', on);
    const v = views.get(card.querySelector('.art'));
    if (v) v.state.targetTheme = on ? 1 : 0;
  };
  card.addEventListener('pointerenter', () => set(true));
  card.addEventListener('pointerleave', () => set(document.activeElement === card));
  card.addEventListener('focus', () => set(true));
  card.addEventListener('blur', () => set(false));
});

/* ---------- Screens ---------- */
// All four images are in the page from the start; the tabs only switch which one shows.
const tabs = $('#shot-tabs');
tabs.innerHTML = shots.map((s, i) => `<button role="tab" id="shot-tab-${i}" aria-controls="shot-${i}" aria-selected="${i === 0}" tabindex="${i ? -1 : 0}">${s.title}</button>`).join('');
$('#shots').innerHTML = shots.map((s, i) => `
  <figure class="shot-panel" id="shot-${i}" role="tabpanel" aria-labelledby="shot-tab-${i}" ${i ? 'hidden' : ''}>
    <img src="${s.src}" width="2266" height="1536" alt="${s.alt}" decoding="async" />
  </figure>`).join('');
const tabButtons = [...tabs.children];
const panels = $$('.shot-panel');
function showShot(i, focus) {
  tabButtons.forEach((b, j) => { b.setAttribute('aria-selected', String(i === j)); b.tabIndex = i === j ? 0 : -1; });
  panels.forEach((p, j) => { p.hidden = i !== j; });
  if (focus) tabButtons[i].focus();
}
tabButtons.forEach((b, i) => {
  b.addEventListener('click', () => showShot(i));
  b.addEventListener('keydown', e => {
    const n = shots.length;
    const next = { ArrowRight: (i + 1) % n, ArrowLeft: (i - 1 + n) % n, Home: 0, End: n - 1 }[e.key];
    if (next !== undefined) { e.preventDefault(); showShot(next, true); }
  });
});
/* ---------- Review: the selection climbs as you read ---------- */
const stepEls = $$('.step');
function onScroll() {
  const mid = innerHeight * 0.5;
  const centers = stepEls.map(el => { const r = el.getBoundingClientRect(); return r.top + r.height / 2; });
  let p = 0;
  if (mid >= centers[centers.length - 1]) p = centers.length - 1;
  else if (mid > centers[0]) {
    for (let i = 0; i < centers.length - 1; i++) {
      if (mid < centers[i + 1]) { p = i + (mid - centers[i]) / (centers[i + 1] - centers[i]); break; }
    }
  }
  const active = Math.round(p);
  stepEls.forEach((el, i) => el.classList.toggle('on', i === active));
  $('#review-idx').textContent = pad(active + 1);
  const v = views.get($('[data-art="steps"]'));
  if (v) v.state.progress = p;
  $('.top').classList.toggle('scrolled', scrollY > 8);
}
addEventListener('scroll', onScroll, { passive: true });
addEventListener('resize', onScroll);
onScroll();

/* ---------- Quiet ---------- */
const quietBtn = $('#quiet-toggle');
quietBtn.addEventListener('click', () => {
  const quit = quietBtn.getAttribute('aria-pressed') !== 'true';
  quietBtn.setAttribute('aria-pressed', String(quit));
  quietBtn.textContent = quit ? 'Open' : 'Quit';
  $('#quiet-state').textContent = quit ? 'Quit' : 'Open';
  $('.quiet').classList.toggle('is-quit', quit);
  const v = views.get($('[data-art="toggle"]'));
  if (v) v.state.open = !quit;
});

/* ---------- Copy ---------- */
$('#copy').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText('swift test\nbash scripts/build-app.sh\nopen dist/Viper.app');
    $('#copy').textContent = 'Copied';
    $('#copy-status').textContent = 'Copied';
    setTimeout(() => { $('#copy').textContent = 'Copy'; }, 2000);
  } catch {
    $('#copy-status').textContent = 'Copy failed. Select the text instead.';
  }
});

/* ---------- Menu ---------- */
const menuToggle = $('#menu-toggle');
function setMenu(open) {
  document.body.classList.toggle('menu-open', open);
  menuToggle.setAttribute('aria-expanded', String(open));
  menuToggle.textContent = open ? 'Close' : 'Menu';
}
menuToggle.addEventListener('click', () => setMenu(menuToggle.getAttribute('aria-expanded') !== 'true'));
$$('#menu a').forEach(a => a.addEventListener('click', () => setMenu(false)));
addEventListener('keydown', e => { if (e.key === 'Escape' && document.body.classList.contains('menu-open')) { setMenu(false); menuToggle.focus(); } });

/* ---------- Motion ---------- */
// The drawings hold still for people who ask the system for reduced motion.
function applyMotion() { paused = reduced.matches; stage?.pause(paused); }
reduced.addEventListener('change', applyMotion);
applyMotion();
