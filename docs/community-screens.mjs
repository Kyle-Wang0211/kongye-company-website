import * as THREE from './viewer/vendor/three/build/three.module.js';
import { gsap } from './vendor/gsap/gsap-core.js';
import { createActivityScene } from './community-particle-scenes.mjs?v=particle-windows-20261114';
import {
  activityPageUrl,
  listActivities,
  selectedActivityIndex,
} from './community-activities.mjs?v=cover16x9-20261110-r2';

const stage = document.querySelector('.community-screen-stage');
const switcher = document.querySelector('.community-screen-switcher');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const phase = { value: 0 };
let rows = [];
let panes = [];
let worlds = [];
let renderer;
let timeline;
let width = 1;
let height = 1;
let selected = -1;
let loading = false;
let visible = true;
let pageActive = true;
let activeId = null;
let pointerStart = null;
let suppressClickUntil = 0;
try {
  activeId = sessionStorage.getItem('pw-community-activity');
} catch {}

function remember(index) {
  if (selected === index) return;
  selected = index;
  activeId = rows[index].id;
  [...switcher.children].forEach((button, i) => {
    button.setAttribute('aria-pressed', String(i === index));
  });
  try {
    sessionStorage.setItem('pw-community-activity', activeId);
  } catch {}
}

function render() {
  if (!renderer || !rows.length) return;
  const count = panes.length;
  const paneWidth = panes[0][0].getBoundingClientRect().width;
  const pitch = paneWidth + width * 0.04;
  const centeredLeft = (width - paneWidth) / 2;
  const cycle = count * pitch;
  let nearest = 0;
  let nearestDistance = Infinity;

  renderer.setScissorTest(false);
  renderer.setClearColor(0xffffff, 1);
  renderer.clear();
  // Every world keeps the full-stage viewport. Only the reveal rectangles move.
  renderer.setViewport(0, 0, width, height);
  renderer.setScissorTest(true);
  panes.forEach((copies, index) => {
    const raw = index * pitch + centeredLeft - phase.value * pitch;
    const base = THREE.MathUtils.euclideanModulo(raw + pitch, cycle) - pitch;
    copies.forEach((pane, copy) => {
      const left = base + copy * cycle;
      pane.style.transform = `translate3d(${left}px,0,0)`;
      const inView = left < width && left + paneWidth > 0;
      pane.inert = !inView;
      pane.setAttribute('aria-hidden', String(!inView));
      if (!inView) return;
      const distance = Math.abs(left + paneWidth / 2 - width / 2);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = index % rows.length;
      }
      const clippedLeft = Math.max(0, Math.ceil(left));
      const clippedRight = Math.min(width, Math.floor(left + paneWidth));
      if (clippedRight <= clippedLeft) return;
      const world = worlds[index % rows.length];
      renderer.setScissor(clippedLeft, 0, clippedRight - clippedLeft, height);
      renderer.clear();
      renderer.render(world.scene, world.camera);
    });
  });
  renderer.setScissorTest(false);
  remember(nearest);
}

function updatePlayback() {
  const playing = visible && pageActive && !document.hidden && !reducedMotion.matches && !pointerStart;
  if (playing) timeline?.play();
  else timeline?.pause();
}

function resize() {
  width = Math.max(1, Math.round(stage.clientWidth));
  height = Math.max(1, Math.round(stage.clientHeight));
  if (!renderer) return;
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
  renderer.setSize(width, height, false);
  worlds.forEach((world) => world.resize(width, height));
  render();
}

function select(index) {
  if (!rows.length) return;
  const target = THREE.MathUtils.euclideanModulo(index, rows.length);
  // One activity advances one window pitch. The timeline wraps outside the stage.
  timeline?.time(target * 5);
  phase.value = target;
  render();
  updatePlayback();
}

function build(next) {
  timeline?.kill();
  worlds.forEach((world) => world.dispose());
  rows = next;
  worlds = rows.map(createActivityScene);
  panes = [];
  selected = -1;
  stage.replaceChildren();
  switcher.replaceChildren();
  if (!rows.length) {
    stage.textContent = '暂无已发布活动';
    return;
  }
  if (!renderer) {
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.autoClear = false;
    renderer.domElement.className = 'community-particle-canvas';
    renderer.domElement.setAttribute('aria-hidden', 'true');
  }
  stage.append(renderer.domElement);
  // Repeating existing activities fills the three windows when fewer are published.
  const paneCount = rows.length < 3 ? rows.length * 3 : rows.length;
  for (let index = 0; index < paneCount; index += 1) {
    const row = rows[index % rows.length];
    const copies = [];
    for (let copy = 0; copy < 2; copy += 1) {
      const link = document.createElement('a');
      link.className = 'community-feature-screen community-screen-event';
      link.href = activityPageUrl(row.slug);
      link.setAttribute('aria-label', row.content.title);
      const title = document.createElement('span');
      title.className = 'community-screen-title';
      title.textContent = row.content.title;
      link.append(title);
      stage.append(link);
      copies.push(link);
    }
    panes.push(copies);
  }
  rows.forEach((row, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'community-screen-choice';
    button.setAttribute('aria-label', row.content.title);
    const dot = document.createElement('span');
    dot.className = 'community-screen-dot';
    dot.setAttribute('aria-hidden', 'true');
    button.append(dot);
    button.addEventListener('click', () => select(index));
    switcher.append(button);
  });
  const initialSelection = selectedActivityIndex(rows, activeId);
  phase.value = 0;
  timeline = gsap.timeline({ repeat: -1, paused: true, onUpdate: render });
  timeline.to(phase, { value: paneCount, duration: paneCount * 5, ease: 'none' });
  resize();
  select(initialSelection);
}

async function refresh() {
  if (loading) return;
  loading = true;
  try {
    const next = await listActivities();
    const identity = (items) => items.map((row) => `${row.id}:${row.revision}`).join('|');
    if (!renderer || identity(next) !== identity(rows)) build(next);
  } catch (error) {
    console.error('Activity windows could not load', error);
    if (!rows.length) {
      stage.replaceChildren();
      const retry = document.createElement('button');
      retry.className = 'community-screen-retry';
      retry.textContent = '活动暂不可用，点击重试';
      retry.addEventListener('click', refresh);
      stage.append(retry);
    }
  } finally {
    loading = false;
  }
}

switcher.addEventListener('keydown', (event) => {
  if (!rows.length || !['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  event.preventDefault();
  const index = event.key === 'Home' ? 0 : event.key === 'End' ? rows.length - 1
    : selected + (event.key === 'ArrowLeft' ? -1 : 1);
  select(index);
  switcher.children[selected].focus();
});
stage.addEventListener('pointerdown', (event) => {
  if (!event.isPrimary || event.button !== 0) return;
  pointerStart = { x: event.clientX, y: event.clientY, id: event.pointerId };
  updatePlayback();
});
stage.addEventListener('pointerup', (event) => {
  if (!pointerStart || event.pointerId !== pointerStart.id) return;
  const dx = event.clientX - pointerStart.x;
  const dy = event.clientY - pointerStart.y;
  pointerStart = null;
  if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) {
    select(selected + (dx < 0 ? 1 : -1));
    suppressClickUntil = performance.now() + 250;
  }
  updatePlayback();
});
function releasePointer() {
  pointerStart = null;
  updatePlayback();
}
stage.addEventListener('pointercancel', releasePointer);
window.addEventListener('pointerup', releasePointer);
stage.addEventListener('click', (event) => {
  if (performance.now() < suppressClickUntil) event.preventDefault();
}, true);
new ResizeObserver(resize).observe(stage);
new IntersectionObserver(([entry]) => {
  visible = entry.isIntersecting;
  updatePlayback();
}).observe(stage);
reducedMotion.addEventListener('change', updatePlayback);
document.addEventListener('visibilitychange', () => {
  updatePlayback();
  if (!document.hidden) void refresh();
});
window.addEventListener('pagehide', () => {
  pageActive = false;
  updatePlayback();
});
window.addEventListener('pageshow', () => {
  pageActive = true;
  updatePlayback();
  void refresh();
});
void refresh();
