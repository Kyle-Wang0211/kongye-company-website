import './vendor/masonry/masonry.pkgd.js?v=4.2.2';

// The upstream library owns shortest-column placement. This adapter only keeps
// its item list and measurements in sync with the existing paginated feed.
export function attachCommunityMasonry(grid) {
  const selector = '.community-card, .community-skeleton';
  grid.classList.add('is-masonry');
  const layout = new window.Masonry(grid, {
    itemSelector: selector,
    columnWidth: selector,
    percentPosition: true,
    horizontalOrder: false,
    transitionDuration: 0,
    resize: false,
    initLayout: false,
  });
  let pendingFrame = 0;
  let reloadItems = true;
  let gridWidth;
  const sizes = new WeakMap();

  function scheduleLayout() {
    if (pendingFrame) return;
    pendingFrame = requestAnimationFrame(() => {
      pendingFrame = 0;
      layout.option({gutter: parseFloat(getComputedStyle(grid).columnGap) || 0});
      if (reloadItems) {
        layout.reloadItems();
        reloadItems = false;
      }
      layout.layout();
    });
  }

  const resizeObserver = new ResizeObserver(entries => {
    for (const entry of entries) {
      const {width, height} = entry.contentRect;
      if (entry.target === grid) {
        if (width === gridWidth) continue;
        gridWidth = width;
      } else {
        const previous = sizes.get(entry.target);
        if (previous?.width === width && previous?.height === height) continue;
        sizes.set(entry.target, {width, height});
      }
      scheduleLayout();
    }
  });
  const childrenObserver = new MutationObserver(records => {
    for (const record of records) {
      for (const node of record.removedNodes) {
        if (node.nodeType === 1) resizeObserver.unobserve(node);
      }
      for (const node of record.addedNodes) {
        if (node.nodeType === 1 && node.matches(selector)) resizeObserver.observe(node);
      }
    }
    reloadItems = true;
    scheduleLayout();
  });
  resizeObserver.observe(grid);
  for (const child of grid.querySelectorAll(selector)) resizeObserver.observe(child);
  childrenObserver.observe(grid, {childList: true});
  window.addEventListener('pageshow', scheduleLayout);
  scheduleLayout();
}
