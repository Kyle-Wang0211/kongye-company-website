(() => {
  const button = document.getElementById('motion-toggle');
  const label = button.querySelector('.motion-label');
  const symbol = button.querySelector('.motion-symbol');
  const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
  let paused = preference.matches;
  function render() {
    document.documentElement.dataset.motion = paused ? 'paused' : 'running';
    button.setAttribute('aria-pressed', String(paused));
    button.setAttribute('aria-label', preference.matches ? '系统已启用减少动态效果' : paused ? '播放几何动效' : '暂停几何动效');
    label.textContent = preference.matches ? '已减少动态效果' : paused ? '播放动效' : '暂停动效';
    symbol.textContent = paused ? '▷' : 'Ⅱ';
    button.disabled = preference.matches;
  }
  button.addEventListener('click', () => { paused = !paused; render(); });
  preference.addEventListener('change', () => { paused = preference.matches; render(); });
  render();
})();
