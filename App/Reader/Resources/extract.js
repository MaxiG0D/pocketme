(function () {
  const article = new Readability(document.cloneNode(true)).parse();
  if (!article || !article.content || !article.textContent.trim()) throw new Error('No readable article found');
  const root = document.createElement('div'); root.innerHTML = article.content;
  const resolve = value => { if (typeof value !== 'string' || !value.trim()) return null; try { const u = new URL(value, document.baseURI); return ['http:', 'https:'].includes(u.protocol) ? u.href : null; } catch { return null; } };
  const imageSource = img => {
    const candidates = (img.getAttribute('data-srcset') || img.getAttribute('srcset') || '').split(',')
      .map(item => item.trim().split(/\s+/)).filter(parts => resolve(parts[0]))
      .sort((a, b) => (parseFloat(b[1]) || 1) - (parseFloat(a[1]) || 1));
    return resolve(img.getAttribute('data-src') || img.getAttribute('data-original') || img.getAttribute('data-lazy-src'))
      || (candidates.length ? resolve(candidates[0][0]) : null) || resolve(img.getAttribute('src'));
  };
  const images = Array.from(root.querySelectorAll('img'));
  const imageCandidates = Array.from(new Set([
    ...Array.from(document.querySelectorAll('meta[property="og:image:secure_url"],meta[property="og:image"],meta[property="og:image:url"],meta[name="twitter:image"],meta[property="twitter:image"],meta[name="twitter:image:src"]')).map(meta => resolve(meta.content)),
    ...Array.from(document.querySelectorAll('link[rel="image_src"]')).map(link => resolve(link.href)),
    ...images.filter(img => {
      const width = Number(img.getAttribute('width'));
      const height = Number(img.getAttribute('height'));
      return (!width || width >= 120) && (!height || height >= 80);
    }).map(imageSource)
  ].filter(Boolean))).slice(0, 8);
  const lead = imageCandidates[0] || null;
  root.querySelectorAll('iframe').forEach(frame => {
    const url = resolve(frame.src);
    if (url && /(^|\.)youtube(-nocookie)?\.com$/.test(new URL(url).hostname)) {
      const a = document.createElement('a'); a.href = url; a.textContent = 'Watch video on YouTube'; frame.replaceWith(a);
    } else frame.remove();
  });
  root.querySelectorAll('script,style,object,embed,form,input,button,textarea,select,link,meta,base,svg,math,noscript').forEach(e => e.remove());
  root.querySelectorAll('font,center').forEach(e => e.replaceWith(...e.childNodes));
  root.querySelectorAll('*').forEach(e => {
    for (const a of Array.from(e.attributes)) {
      if (/^on/i.test(a.name) || ['style', 'srcdoc', 'id', 'class', 'autofocus', 'contenteditable'].includes(a.name)) e.removeAttribute(a.name);
    }
    if (e.tagName === 'IMG') {
      const src = imageSource(e);
      if (!src) { e.remove(); return; }
      e.setAttribute('src', src); e.removeAttribute('srcset'); e.removeAttribute('sizes');
      e.removeAttribute('width'); e.removeAttribute('height'); e.removeAttribute('loading');
    }
    if (e.hasAttribute('href')) {
      const url = resolve(e.getAttribute('href'));
      if (url) e.setAttribute('href', url); else e.removeAttribute('href');
    }
    if (['AUDIO', 'VIDEO', 'SOURCE'].includes(e.tagName)) e.remove();
  });
  root.querySelectorAll('p').forEach(p => { if (!p.textContent.trim() && !p.querySelector('img')) p.remove(); });
  const text = root.textContent.trim();
  const words = text ? text.split(/\s+/u).length : 0;
  return JSON.stringify({ title: article.title || document.title, siteName: document.querySelector('meta[property="og:site_name"]')?.content || article.siteName || location.hostname.replace(/^www\./, ''), author: article.byline, excerpt: article.excerpt?.slice(0,200), leadImageURL: lead, imageCandidates, content: root.innerHTML, wordCount: words });
})();
