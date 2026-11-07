(() => {
  const article = document.querySelector('article');
  const status = document.querySelector('#status');
  const progress = document.querySelector('.reading-progress');
  const sections = [...article.querySelectorAll('section[id]')];
  const tocLinks = [...document.querySelectorAll('.toc a')];
  const mobileToc = document.querySelector('.mobile-toc');
  const words = article.textContent.trim().split(/\s+/).length;
  document.querySelector('#reading-time').textContent = `${Math.ceil(words / 200)} min read`;

  function updateReadingPosition() {
    const start = article.getBoundingClientRect().top + window.scrollY;
    const end = start + article.offsetHeight - window.innerHeight;
    const value = Math.min(1, Math.max(0, (window.scrollY - start) / Math.max(1, end - start)));
    progress.style.transform = `scaleX(${value})`;
    let current = sections[0].id;
    for (const section of sections) {
      if (section.getBoundingClientRect().top <= 150) current = section.id;
    }
    for (const link of tocLinks) {
      if (link.hash === `#${current}`) link.setAttribute('aria-current', 'location');
      else link.removeAttribute('aria-current');
    }
  }

  let scheduled = false;
  function scheduleUpdate() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      updateReadingPosition();
      scheduled = false;
    });
  }
  window.addEventListener('scroll', scheduleUpdate, { passive: true });
  window.addEventListener('resize', scheduleUpdate);
  window.addEventListener('load', scheduleUpdate);
  updateReadingPosition();

  mobileToc.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', () => { mobileToc.open = false; });
  });

  function highlight(code) {
    const fragment = document.createDocumentFragment();
    code.textContent.split('\n').forEach((line, index) => {
      if (index) fragment.append('\n');
      const span = document.createElement('span');
      if (/^\s*#/.test(line)) span.className = 'code-comment';
      else if (/^\[.+\]$/.test(line)) span.className = 'code-section';
      else if (/^[A-Za-z]+\s*=/.test(line)) {
        const split = line.indexOf('=');
        const key = document.createElement('span');
        key.className = 'code-key';
        key.textContent = line.slice(0, split);
        span.append(key, line.slice(split));
        fragment.append(span);
        return;
      }
      span.textContent = line;
      fragment.append(span);
    });
    code.replaceChildren(fragment);
  }

  document.querySelectorAll('.code-block').forEach(block => {
    const code = block.querySelector('code');
    const pre = block.querySelector('pre');
    const label = block.querySelector('.file-label').textContent;
    pre.tabIndex = 0;
    pre.setAttribute('aria-label', `${label}, scrollable code`);
    highlight(code);
    const button = document.createElement('button');
    button.className = 'copy-button';
    button.type = 'button';
    button.textContent = 'Copy';
    button.setAttribute('aria-label', `Copy code: ${label}`);
    button.addEventListener('click', async () => {
      try {
        if (!navigator.clipboard) throw new Error('Clipboard unavailable');
        await navigator.clipboard.writeText(code.textContent);
        button.textContent = 'Copied ✓';
        status.textContent = `Copied code from ${label}.`;
      } catch {
        // Local files and plain HTTP may deny clipboard access; keep manual copying usable.
        const range = document.createRange();
        range.selectNodeContents(code);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        button.textContent = 'Selected';
        status.textContent = 'Code selected. Press Control+C or Command+C to copy.';
      }
      setTimeout(() => { button.textContent = 'Copy'; }, 2200);
    });
    block.querySelector('.code-header').append(button);
  });

  const dialog = document.querySelector('.lightbox');
  const dialogImage = dialog.querySelector('img');
  let previousOverflow = '';
  document.querySelectorAll('.figure-link').forEach(link => {
    const img = link.querySelector('img');
    link.setAttribute('aria-label', `Enlarge illustration: ${img.alt}`);
    link.addEventListener('click', event => {
      if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || !dialog.showModal) return;
      event.preventDefault();
      dialogImage.src = link.href;
      dialogImage.alt = img.alt;
      document.querySelector('#lightbox-title').textContent = link.closest('figure').querySelector('figcaption').textContent;
      previousOverflow = document.body.style.overflow;
      document.body.style.overflow = 'hidden';
      dialog.showModal();
    });
  });
  dialog.querySelector('.lightbox-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });
  dialog.addEventListener('close', () => { document.body.style.overflow = previousOverflow; });

  const printButton = document.querySelector('.print-button');
  printButton.hidden = false;
  printButton.addEventListener('click', () => window.print());
  let collapsedDetails = [];
  window.addEventListener('beforeprint', () => {
    // Closed disclosures would otherwise omit the original screenshots from the printed article.
    collapsedDetails = [...article.querySelectorAll('details:not([open])')];
    collapsedDetails.forEach(detail => { detail.open = true; });
  });
  window.addEventListener('afterprint', () => {
    collapsedDetails.forEach(detail => { detail.open = false; });
    collapsedDetails = [];
  });
})();
