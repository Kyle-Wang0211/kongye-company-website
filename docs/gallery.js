(() => {
  const cards = Array.from(document.querySelectorAll('.scan-card'));
  cards.forEach(card => {
    card.addEventListener('toggle', () => {
      const frame = card.querySelector('iframe');
      card.querySelector('summary > span').firstChild.nodeValue = card.open ? '收起 3D ' : '旋转查看 3D ';
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
