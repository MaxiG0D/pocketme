(() => {
  const post = (action, extra = {}) => window.webkit?.messageHandlers.reader?.postMessage({action,...extra});
  let restored = false, restoring = false, last = 0, desired = 0, styleKey = '';
  function progress(force = false) {
    if (!restored) return;
    const now = Date.now(); if (!force && now - last < 200) return; last = now;
    const height = document.documentElement.scrollHeight - innerHeight;
    post('progress', {value: height > 0 ? Math.max(0,Math.min(1,scrollY / height)) : 0});
  }
  window.pocketmeConfigure = config => {
    const anchor = restored ? scrollY / Math.max(1,document.documentElement.scrollHeight - innerHeight) : config.progress;
    const key = [config.theme, config.font, config.size, config.mac].join(':');
    const styleChanged = key !== styleKey; styleKey = key;
    document.documentElement.className = [config.theme, config.font === 'sans' ? 'sans' : '', config.mac ? 'mac' : ''].join(' ');
    document.documentElement.style.setProperty('--size', config.size + 'px');
    const favorite = document.querySelector('[data-action="favorite"]'); if (favorite) favorite.textContent = config.favorite ? 'Favorited' : 'Favorite';
    const archive = document.querySelector('[data-action="archive"]'); if (archive) archive.textContent = config.archived ? 'Unarchive' : 'Archive';
    const upnext = document.querySelector('.upnext');
    if (upnext) {
      upnext.hidden = !config.nextTitle;
      const button = upnext.querySelector('button'); if (button) button.textContent = config.nextTitle || '';
    }
    if (!restored) {
      desired = config.progress || 0;
      if (!restoring) {
        restoring = true;
        const images = Array.from(document.images).map(img => img.complete ? Promise.resolve() : new Promise(resolve => { img.addEventListener('load', resolve, {once:true}); img.addEventListener('error', resolve, {once:true}); setTimeout(resolve, 2000); }));
        Promise.all([document.fonts.ready, ...images]).then(() => requestAnimationFrame(() => { scrollTo(0,desired * Math.max(0,document.documentElement.scrollHeight-innerHeight)); restored = true; }));
      }
    } else if (styleChanged) {
      requestAnimationFrame(() => scrollTo(0,(anchor || 0) * Math.max(0,document.documentElement.scrollHeight-innerHeight)));
    }
  };
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-action]');
    if (button) { event.preventDefault(); progress(true); post(button.dataset.action); }
  });
  document.addEventListener('scroll', () => progress(), {passive:true});
  window.addEventListener('pagehide', () => progress(true));
  document.addEventListener('keydown', event => {
    if (['INPUT','TEXTAREA'].includes(event.target.tagName)) return;
    if (event.key === 'Escape') { post('back'); event.preventDefault(); }
    else if (!event.metaKey && !event.ctrlKey && event.key.toLowerCase() === 'e') { post('archive'); event.preventDefault(); }
    else if (!event.metaKey && !event.ctrlKey && event.key.toLowerCase() === 'f') { post('favorite'); event.preventDefault(); }
    else if (event.metaKey && ['+','=','-'].includes(event.key)) { post(event.key === '-' ? 'smaller' : 'larger'); event.preventDefault(); }
  });
  window.pocketmeProgress = () => { progress(true); };
  post('ready');
})();
