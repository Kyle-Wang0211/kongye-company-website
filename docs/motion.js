(async () => {
  const {t,localeReady,localeEvent}=await import('./site-l10n.mjs?v=shared-community-20261106-v40');await localeReady;
  const button = document.getElementById('motion-toggle');
  if(!button)return;
  const label = button.querySelector('.motion-label');
  const symbol = button.querySelector('.motion-symbol');
  const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
  let paused = preference.matches;
  function render() {
    document.documentElement.dataset.motion = paused ? 'paused' : 'running';
    button.setAttribute('aria-pressed', String(paused));
    button.setAttribute('aria-label', preference.matches ? t('siteMotionReducedAria') : paused ? t('siteMotionPlayAria') : t('siteMotionPauseAria'));
    label.textContent = preference.matches ? t('siteMotionReduced') : paused ? t('siteMotionPlay') : t('siteMotionPause');
    symbol.textContent = paused ? '▷' : 'Ⅱ';
    button.disabled = preference.matches;
  }
  button.addEventListener('click', () => { paused = !paused; render(); });
  preference.addEventListener('change', () => { paused = preference.matches; render(); });
  window.addEventListener(localeEvent,render);
  render();
})();
