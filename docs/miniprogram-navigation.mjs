// Keep the shared website pages inside the mini program's mobile community.
export function miniProgramDestination(href, currentHref) {
  const current = new URL(currentHref);
  const destination = new URL(href, current);
  if (current.searchParams.get('mini') !== '1' || destination.origin !== current.origin) {
    return destination.href;
  }
  if (destination.pathname === '/screen.html') {
    destination.searchParams.set('mini', '1');
  } else if (['/', '/index.html', '/community/', '/community/index.html'].includes(destination.pathname)) {
    destination.pathname = '/miniprogram/';
    destination.searchParams.set('feed', '1');
  }
  return destination.href;
}

export function installMiniProgramNavigation() {
  if (new URL(location.href).searchParams.get('mini') !== '1') return;
  const adapt = anchor => {
    anchor.href = miniProgramDestination(anchor.getAttribute('href'), location.href);
  };
  document.querySelectorAll('a[href]').forEach(adapt);
  // Event delegation also covers links mounted later by the original subpages.
  document.addEventListener('click', event => {
    const anchor = event.target.closest?.('a[href]');
    if (anchor) adapt(anchor);
  }, true);
}
