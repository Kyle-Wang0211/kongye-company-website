import {
  carouselPosition,
  listActivities,
  selectedActivityIndex,
} from './community-activities.mjs?v=activities-20261110';
const stage = document.querySelector('.community-screen-stage');
const switcher = document.querySelector('.community-screen-switcher');
let rows = [];
let selected = 0;
let rotationTimer;
let loading = false;
let activeId = null;
try {
  activeId = sessionStorage.getItem('pw-community-activity');
} catch {}
function scheduleRotation() {
  clearTimeout(rotationTimer);
  if (!document.hidden && rows.length > 1) {
    rotationTimer = setTimeout(() => select(selected + 1), 5000);
  }
}
function select(index) {
  if (!rows.length) {
    return;
  }
  selected = (index + rows.length) % rows.length;
  activeId = rows[selected].id;
  [...stage.children].forEach((link, index) => {
    const position = carouselPosition(index, selected, rows.length);
    link.hidden = position === 'hidden';
    link.style.display = link.hidden ? 'none' : '';
    link.dataset.position = position;
    switcher.children[index].setAttribute('aria-pressed', String(index === selected));
  });
  try {
    sessionStorage.setItem('pw-community-activity', activeId);
  } catch {}
  scheduleRotation();
}
async function refresh() {
  if (loading) {
    return;
  }
  loading = true;
  try {
    const next = await listActivities();
    rows = next;
    selected = selectedActivityIndex(rows, activeId);
    stage.replaceChildren();
    switcher.replaceChildren();
    rows.forEach((row, index) => {
      const link = document.createElement('a');
      link.className = 'community-feature-screen community-screen-event';
      link.href = 'screen.html?activity=' + encodeURIComponent(row.slug);
      link.setAttribute('aria-label', row.content.title);
      const image = document.createElement('img');
      image.src = row.content.cover_url;
      image.alt = row.content.title;
      image.width = 1600;
      image.height = 900;
      link.append(image);
      stage.append(link);
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
    if (!rows.length) {
      const message = document.createElement('p');
      message.textContent = '暂无已发布活动';
      message.setAttribute('role', 'status');
      stage.append(message);
      clearTimeout(rotationTimer);
    } else {
      select(selected);
    }
  } catch {
    if (!rows.length) {
      stage.replaceChildren();
      const message = document.createElement('button');
      message.type = 'button';
      message.textContent = '活动暂不可用，点击重试';
      message.addEventListener('click', refresh);
      stage.append(message);
    }
  } finally {
    loading = false;
  }
}
switcher.addEventListener('keydown', (event) => {
  if (!rows.length || !['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) {
    return;
  }
  event.preventDefault();
  select(
    event.key === 'Home'
      ? 0
      : event.key === 'End'
      ? rows.length - 1
      : selected + (event.key === 'ArrowLeft' ? -1 : 1),
  );
  switcher.children[selected].focus();
});
let pointerStart = null;
let suppressClickUntil = 0;
stage.addEventListener('pointerdown', (event) => {
  if (event.isPrimary && event.button === 0) {
    pointerStart = { x: event.clientX, y: event.clientY, id: event.pointerId };
  }
});
stage.addEventListener('pointerup', (event) => {
  if (!pointerStart || event.pointerId !== pointerStart.id) {
    return;
  }
  const horizontalDistance = event.clientX - pointerStart.x;
  const verticalDistance = event.clientY - pointerStart.y;
  pointerStart = null;
  if (
    Math.abs(horizontalDistance) > 40 &&
    Math.abs(horizontalDistance) > Math.abs(verticalDistance)
  ) {
    select(selected + (horizontalDistance < 0 ? 1 : -1));
    suppressClickUntil = performance.now() + 250;
  }
});
stage.addEventListener('pointercancel', () => {
  pointerStart = null;
});
stage.addEventListener('click', (event) => {
  if (performance.now() < suppressClickUntil) {
    event.preventDefault();
  }
}, true);
document.addEventListener('visibilitychange', () => {
  scheduleRotation();
  if (!document.hidden) {
    void refresh();
  }
});
window.addEventListener('pagehide', () => clearTimeout(rotationTimer));
window.addEventListener('pageshow', () => {
  scheduleRotation();
  void refresh();
});
void refresh();
