(async () => {
  const {t,localeReady,localeEvent}=await import('./site-l10n.mjs?v=community-settings-20261103-v10');await localeReady;
  const cards = Array.from(document.querySelectorAll('.scan-card'));
  const render=()=>cards.forEach(card=>{card.querySelector('summary > span').firstChild.nodeValue=t(card.open?'siteGalleryCollapse':'siteGalleryRotate');});
  window.addEventListener(localeEvent,render);render();
  cards.forEach(card => {
    card.addEventListener('toggle', () => {
      const frame = card.querySelector('iframe');
      card.querySelector('summary > span').firstChild.nodeValue = t(card.open ? 'siteGalleryCollapse' : 'siteGalleryRotate');
      if (card.open) {
        cards.forEach(other => {
          if (other !== card) {
            other.querySelector('iframe').removeAttribute('src');
            other.open = false;
          }
        });
        if (!frame.hasAttribute('src')) frame.src = frame.dataset.src;
      } else {
        frame.removeAttribute('src');
      }
    });
  });
})();
