(() => {
  const post = (action, extra = {}) => window.webkit?.messageHandlers.reader?.postMessage({action,...extra});
  let restored = false, restoring = false, last = 0, desired = 0, styleKey = '';
  function progress(force = false) {
    if (!restored) return;
    const now = Date.now(); if (!force && now - last < 200) return; last = now;
    const height = document.documentElement.scrollHeight - innerHeight;
    post('progress', {value: height > 0 ? Math.max(0,Math.min(1,scrollY / height)) : 0});
  }
  // The reading bar lives in the page and moves with a transform, so scrolling never crosses the native bridge.
  const bar = document.createElement('div'), fill = document.createElement('div');
  bar.id = 'readbar';
  bar.style.cssText = 'position:fixed;top:0;left:0;right:0;height:2px;z-index:10;pointer-events:none;overflow:hidden;background:color-mix(in srgb,var(--ink,#1A1A1A) 6%,transparent)';
  fill.style.cssText = 'height:100%;background:var(--accent,#E2562B);transform-origin:0 50%;transform:scaleX(.0001);will-change:transform';
  bar.appendChild(fill); (document.body || document.documentElement).appendChild(bar);
  if (document.body?.classList.contains('video')) bar.hidden = true;
  let range = 0, frame = 0, settle = 0;
  const measure = () => { range = Math.max(0, document.documentElement.scrollHeight - innerHeight); };
  measure();
  if (window.ResizeObserver) new ResizeObserver(measure).observe(document.documentElement);
  window.addEventListener('resize', measure);
  function paint() {
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      fill.style.transform = 'scaleX(' + Math.max(.0001, range > 0 ? Math.min(1, scrollY / range) : 0) + ')';
    });
  }
  window.pocketmeConfigure = config => {
    const anchor = restored ? scrollY / Math.max(1,document.documentElement.scrollHeight - innerHeight) : config.progress;
    const key = [config.theme, config.font, config.size, config.mac].join(':');
    const styleChanged = key !== styleKey; styleKey = key;
    document.documentElement.className = [config.theme, config.font === 'sans' ? 'sans' : '', config.mac ? 'mac' : ''].join(' ');
    document.documentElement.style.setProperty('--size', config.size + 'px');
    const label = (button, text) => { if (button) (button.querySelector('span') || button).textContent = text; };
    const favorite = document.querySelector('[data-action="favorite"]');
    label(favorite, config.favorite ? 'Favorited' : 'Favorite'); favorite?.classList.toggle('on', !!config.favorite);
    label(document.querySelector('[data-action="archive"]'), config.archived ? 'Unarchive' : 'Archive');
    if (!restored) {
      desired = config.progress || 0;
      if (!restoring) {
        restoring = true;
        // 'shown' tells the app the page is styled and in place, so it can fade in.
        const shown = () => requestAnimationFrame(() => requestAnimationFrame(() => post('shown')));
        if (desired > 0.001) {
          const images = Array.from(document.images).map(img => img.complete ? Promise.resolve() : new Promise(resolve => { img.addEventListener('load', resolve, {once:true}); img.addEventListener('error', resolve, {once:true}); setTimeout(resolve, 2000); }));
          Promise.all([document.fonts.ready, ...images]).then(() => requestAnimationFrame(() => { scrollTo(0,desired * Math.max(0,document.documentElement.scrollHeight-innerHeight)); restored = true; measure(); paint(); shown(); }));
        } else { restored = true; document.fonts.ready.then(shown); }
      }
    } else if (styleChanged) {
      requestAnimationFrame(() => { measure(); scrollTo(0,(anchor || 0) * range); paint(); });
    }
  };
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-action]');
    if (button) { event.preventDefault(); progress(true); post(button.dataset.action); }
  });
  document.addEventListener('scroll', () => {
    paint(); progress();
    // The throttle can swallow the last position, so report where scrolling came to rest.
    clearTimeout(settle); settle = setTimeout(() => progress(true), 150);
  }, {passive:true});
  window.addEventListener('pagehide', () => progress(true));
  document.addEventListener('keydown', event => {
    if (['INPUT','TEXTAREA'].includes(event.target.tagName)) return;
    if (event.key === 'Escape') { post('back'); event.preventDefault(); }
    else if (!event.metaKey && !event.ctrlKey && event.key.toLowerCase() === 'e') { post('archive'); event.preventDefault(); }
    else if (!event.metaKey && !event.ctrlKey && event.key.toLowerCase() === 'f') { post('favorite'); event.preventDefault(); }
    else if (event.metaKey && ['+','=','-'].includes(event.key)) { post(event.key === '-' ? 'smaller' : 'larger'); event.preventDefault(); }
  });
  window.pocketmeNext = next => {
    const upnext = document.querySelector('.upnext'); if (!upnext) return;
    upnext.hidden = !next; if (!next) return;
    const thumb = upnext.querySelector('.thumb'), title = upnext.querySelector('.title'), meta = upnext.querySelector('.meta');
    if (title) title.textContent = next.title;
    if (meta) meta.textContent = next.meta;
    if (thumb) {
      thumb.className = 'thumb cover' + next.cover; thumb.textContent = '';
      if (next.image) { const img = document.createElement('img'); img.alt = ''; img.decoding = 'async'; img.src = next.image; thumb.classList.add('photo'); thumb.appendChild(img); }
      else thumb.textContent = next.initial;
    }
  };
  window.pocketmeProgress = () => { progress(true); };
  post('ready');
})();
