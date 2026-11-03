// The PocketMe web app: the library the apps publish as WebArticle records, a clean reader, and archive / favorite.
// Changes go back as WebChange requests that the apps apply (see WebSaveInbox.swift); the web never writes the library itself.
(() => {
  const root = document.getElementById("app");
  if (!root || new URLSearchParams(location.search).has("url")) return;
  const LIBRARY = { zoneName: "WebLibrary" };
  const REQUESTS = { zoneName: "WebSaves" };
  const LIST_KEYS = ["articleID", "url", "title", "siteName", "author", "excerpt", "leadImageURL", "status", "wordCount", "readingMinutes", "savedAt", "archived", "isFavorite", "thumbnail"];
  const $ = (id) => document.getElementById(id);
  const ICON = {
    archive: '<rect x="3" y="4" width="18" height="5" rx="1"/><path d="M5 9v10h14V9M10 13h4"/>',
    star: '<path d="M7 4h10v16l-5-4-5 4z"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    back: '<path d="M15 5l-7 7 7 7"/>',
    aa: '<path d="M3 19l5-13 5 13M5 14h6M15 19l3.5-9 3.5 9M16.5 16h4"/>',
    grid: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
    list: '<path d="M4 7h16M4 12h16M4 17h16"/>',
    open: '<path d="M14 4h6v6M20 4l-9 9M18 14v6H4V6h6"/>'
  };
  const svg = (name) => `<svg aria-hidden="true" viewBox="0 0 24 24">${ICON[name]}</svg>`;
  const store = (key, value) => { try { if (value === undefined) return localStorage.getItem("pocketme." + key); localStorage.setItem("pocketme." + key, value); } catch { return null; } };

  let database = null;
  let articles = [];          // newest first
  let loaded = false;
  let tab = "reading";
  let layout = store("layout") === "grid" ? "grid" : "list";
  // Changes made here show at once; they stay until the app's copy catches up.
  const overrides = new Map();
  const view = (a) => { const o = overrides.get(a.id); return o ? { ...a, ...o } : a; };

  const esc = (text) => String(text == null ? "" : text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const coverIndex = (name) => {
    let hash = 14695981039346656037n;
    for (const byte of new TextEncoder().encode(String(name || "").trim().toLowerCase())) hash = BigInt.asUintN(64, (hash ^ BigInt(byte)) * 1099511628211n);
    return Number(hash % 8n);
  };
  const field = (record, name) => record.fields && record.fields[name] ? record.fields[name].value : undefined;
  const toArticle = (record) => ({
    id: record.recordName, url: field(record, "url") || "", title: field(record, "title") || "", site: field(record, "siteName") || "",
    author: field(record, "author") || "", excerpt: field(record, "excerpt") || "", lead: field(record, "leadImageURL") || "",
    status: field(record, "status") || "pending", words: field(record, "wordCount") || 0, minutes: field(record, "readingMinutes") || 0,
    savedAt: field(record, "savedAt") || 0, archived: field(record, "archived") === 1, favorite: field(record, "isFavorite") === 1,
    thumb: (field(record, "thumbnail") || {}).downloadURL || "", body: field(record, "body")
  });

  // ---- Toast
  let toastTimer;
  function toast(text) {
    const el = $("toast"); el.textContent = text; el.classList.add("on");
    clearTimeout(toastTimer); toastTimer = setTimeout(() => el.classList.remove("on"), 1800);
  }

  // ---- Cloud
  const reason = (error) => String((error && (error.ckErrorCode || error.serverErrorCode || error.message)) || error).slice(0, 80);

  async function connect() {
    CloudKit.configure({ containers: [{
      containerIdentifier: window.POCKETME.container, environment: window.POCKETME.environment,
      apiTokenAuth: { apiToken: window.POCKETME.apiToken, persist: true, signInButton: { id: "sign-in-app", theme: "black" }, signOutButton: { id: "sign-out-app", theme: "black" } }
    }] });
    const container = CloudKit.getDefaultContainer();
    database = container.privateCloudDatabase;
    const gate = (text, signIn) => { $("gate").hidden = false; $("library").hidden = true; $("reader").hidden = true; $("gate-status").textContent = text; $("gate-signin").hidden = !signIn; };
    const proceed = async (user) => {
      if (user && user.hasSignedIn !== false && user.userRecordName) { $("gate").hidden = true; await route(true); }
      else gate("", true);
    };
    try { await proceed(await container.setUpAuth()); } catch (error) { gate(reason(error), false); return; }
    container.whenUserSignsIn().then(proceed);
  }

  async function loadLibrary() {
    const all = [];
    let marker;
    do {
      const response = await database.performQuery(
        { recordType: "WebArticle", sortBy: [{ fieldName: "savedAt", ascending: false }] },
        { zoneID: LIBRARY, desiredKeys: LIST_KEYS, resultsLimit: 200, continuationMarker: marker });
      if (response.hasErrors) {
        const code = response.errors[0].serverErrorCode;
        if (code === "ZONE_NOT_FOUND") break;
        throw response.errors[0];
      }
      for (const record of response.records || []) if (record.recordName) all.push(toArticle(record));
      marker = response.moreComing ? response.continuationMarker : null;
    } while (marker);
    articles = all.sort((a, b) => b.savedAt - a.savedAt);
    for (const [id, o] of overrides) {
      const a = articles.find((x) => x.id === id);
      if (!a || ((o.archived === undefined || o.archived === a.archived) && (o.favorite === undefined || o.favorite === a.favorite))) overrides.delete(id);
    }
    loaded = true;
  }

  async function loadBody(article) {
    if (article.body !== undefined) return article;
    const response = await database.fetchRecords([article.id], { zoneID: LIBRARY, desiredKeys: ["body"] });
    if (response.hasErrors) throw response.errors[0];
    article.body = field(response.records[0], "body") || "";
    return article;
  }

  async function sendChange(article, action) {
    const response = await database.saveRecords({
      recordType: "WebChange", fields: { articleID: { value: article.id }, action: { value: action }, at: { value: Date.now() } }
    }, { zoneID: REQUESTS });
    if (response.hasErrors) throw response.errors[0];
  }

  async function saveLink(url) {
    const response = await database.saveRecords({
      recordType: "SaveRequest", fields: { url: { value: url }, title: { value: "" }, savedAt: { value: Date.now() } }
    }, { zoneID: REQUESTS });
    if (response.hasErrors) throw response.errors[0];
  }

  // ---- Changes
  async function change(article, kind) {
    const now = view(article);
    const next = kind === "archive" ? { archived: !now.archived } : { favorite: !now.favorite };
    overrides.set(article.id, { ...overrides.get(article.id), ...next });
    const action = kind === "archive" ? (next.archived ? "archive" : "unarchive") : (next.favorite ? "favorite" : "unfavorite");
    toast(kind === "archive" ? (next.archived ? "Archived" : "Moved to Reading") : (next.favorite ? "Favorited" : "Removed from Favorites"));
    render();
    try { await sendChange(article, action); }
    catch (error) {
      overrides.delete(article.id);
      toast("Couldn’t save that change");
      console.error(error);
      render();
    }
  }

  // ---- Library
  function visible() {
    const list = articles.map(view);
    if (tab === "archive") return list.filter((a) => a.archived);
    if (tab === "favorites") return list.filter((a) => a.favorite && !a.archived);
    return list.filter((a) => !a.archived);
  }

  function row(a) {
    const site = a.site || (a.url ? new URL(a.url).host.replace(/^www\./, "") : "");
    const meta = [site, a.minutes ? a.minutes + " min" : ""].filter(Boolean).join(" · ");
    const art = a.thumb ? `<img src="${esc(a.thumb)}" alt="" loading="lazy">` : `<div class="cover cover${coverIndex(site)}">${esc((site || "P").slice(0, 1).toUpperCase())}</div>`;
    const dot = a.status === "pending" ? '<span class="pending" role="img" aria-label="Preparing"></span>' : "";
    return `<li class="row" data-id="${esc(a.id)}" tabindex="0" role="link"><div class="thumb">${art}</div>
      <div class="info"><span class="title">${esc(a.title || site)}</span><span class="meta">${dot}${esc(meta)}</span></div>
      <div class="actions"><button class="icon-btn" data-act="favorite" aria-label="Favorite" aria-pressed="${a.favorite}">${svg("star")}</button>
      <button class="icon-btn" data-act="archive" aria-label="${a.archived ? "Move to Reading" : "Archive"}">${svg("archive")}</button></div></li>`;
  }

  function renderLibrary() {
    document.title = "Pocket Me";
    document.body.style.background = "";
    document.querySelectorAll(".tab").forEach((t) => t.setAttribute("aria-selected", String(t.dataset.tab === tab)));
    $("layout").innerHTML = svg(layout === "grid" ? "list" : "grid");
    $("layout").setAttribute("aria-label", layout === "grid" ? "List" : "Grid");
    const rows = $("rows");
    rows.className = "rows" + (layout === "grid" ? " grid" : "");
    if (!loaded) { rows.innerHTML = '<li class="sk"></li>'.repeat(5); return; }
    const list = visible();
    if (!list.length) {
      const text = !articles.length ? "Open PocketMe on your phone or Mac" : tab === "archive" ? "Nothing archived" : tab === "favorites" ? "No favorites" : "All caught up";
      rows.innerHTML = `<li class="empty">${text}</li>`;
      return;
    }
    rows.innerHTML = list.map(row).join("");
  }

  // ---- Reader
  const prefs = { theme: store("theme") || "auto", font: store("font") || "serif", size: Number(store("size")) || 19 };
  let current = null;

  // Keeps what a reading page needs and drops anything that can run or load another page.
  function clean(html) {
    const doc = new DOMParser().parseFromString("<body>" + html + "</body>", "text/html");
    doc.querySelectorAll("script,style,iframe,object,embed,form,link,meta,base,noscript,svg,video,audio,canvas").forEach((n) => n.remove());
    doc.body.querySelectorAll("*").forEach((n) => {
      for (const attr of [...n.attributes]) {
        const name = attr.name.toLowerCase();
        if (name.startsWith("on") || name === "style" || name === "srcdoc") n.removeAttribute(attr.name);
        else if ((name === "href" || name === "src") && !/^(https?:|mailto:|#|data:image\/)/i.test(attr.value.trim())) n.removeAttribute(attr.name);
      }
      if (n.tagName === "A") { n.target = "_blank"; n.rel = "noopener noreferrer"; }
      if (n.tagName === "IMG") { n.loading = "lazy"; n.referrerPolicy = "no-referrer"; n.removeAttribute("srcset"); }
    });
    return doc.body.innerHTML;
  }

  function applyPrefs() {
    const reader = $("reader");
    reader.dataset.theme = prefs.theme; reader.dataset.font = prefs.font;
    reader.style.setProperty("--size", prefs.size + "px");
    document.querySelectorAll("[data-pref]").forEach((b) => b.setAttribute("aria-pressed", String(String(prefs[b.dataset.pref]) === b.dataset.value)));
    if (!$("reader").hidden) requestAnimationFrame(() => { document.body.style.background = getComputedStyle(reader).backgroundColor; });
  }

  function renderReader() {
    const a = view(current);
    document.title = a.title || "Pocket Me";
    const site = a.site || (a.url ? new URL(a.url).host.replace(/^www\./, "") : "");
    const kicker = [site, a.minutes ? a.minutes + " min" : ""].filter(Boolean).join(" · ");
    const lead = a.lead && /^https?:/i.test(a.lead) ? `<img class="lead" alt="" src="${esc(a.lead)}" referrerpolicy="no-referrer">` : "";
    let body;
    if (a.body === undefined) body = "";
    else if (a.body) body = `<div class="body">${clean(a.body)}</div>`;
    else body = `<a class="original" href="${esc(a.url)}" target="_blank" rel="noopener noreferrer">Open original</a>`;
    $("page").innerHTML = `<div class="kicker">${esc(kicker)}</div><h1>${esc(a.title)}</h1>${a.body === "" ? "" : lead}${body}
      <div class="end"><button class="btn primary" data-act="archive">${svg("archive")}<span>${a.archived ? "Move to Reading" : "Archive"}</span></button>
      <button class="btn outline" data-act="favorite" aria-pressed="${a.favorite}">${svg("star")}<span>Favorite</span></button></div>`;
    const fav = $("bar-fav"); fav.setAttribute("aria-pressed", String(a.favorite));
    $("bar-archive").setAttribute("aria-label", a.archived ? "Move to Reading" : "Archive");
    applyPrefs();
  }

  async function openReader(id) {
    const found = articles.find((x) => x.id === id);
    if (!found) { location.hash = ""; return; }
    current = found;
    $("library").hidden = true; $("reader").hidden = false;
    window.scrollTo(0, 0);
    renderReader();
    try { await loadBody(found); } catch (error) { console.error(error); found.body = ""; }
    if (current === found) renderReader();
  }

  // ---- Routing
  async function route(fresh) {
    const match = /^#\/a\/(.+)$/.exec(location.hash);
    if (fresh || !loaded) {
      $("library").hidden = false; $("reader").hidden = true; renderLibrary();
      try { await loadLibrary(); } catch (error) { console.error(error); loaded = true; toast("Couldn’t load your library"); }
    }
    if (match) return openReader(decodeURIComponent(match[1]));
    current = null;
    $("reader").hidden = true; $("library").hidden = false; $("prefs").hidden = true;
    renderLibrary();
  }
  const render = () => { if (current) renderReader(); else renderLibrary(); };

  // ---- Wiring
  function wire() {
    root.querySelectorAll(".tab").forEach((t) => t.addEventListener("click", () => { tab = t.dataset.tab; renderLibrary(); }));
    $("layout").addEventListener("click", () => { layout = layout === "grid" ? "list" : "grid"; store("layout", layout); renderLibrary(); });
    $("add").addEventListener("click", () => { const form = $("save-form"); form.hidden = !form.hidden; if (!form.hidden) $("save-url").focus(); });
    $("save-form").addEventListener("submit", async (event) => {
      event.preventDefault();
      const input = $("save-url");
      let value = input.value.trim();
      if (!value) return;
      if (!/^[a-z][a-z0-9+.-]*:/i.test(value)) value = "https://" + value;
      try {
        const parsed = new URL(value);
        if (!/^https?:$/.test(parsed.protocol)) throw new Error("scheme");
        await saveLink(parsed.href);
        input.value = ""; $("save-form").hidden = true; toast("Saved!");
      } catch (error) { console.error(error); toast("Can’t save this link"); }
    });
    $("rows").addEventListener("click", (event) => {
      const rowEl = event.target.closest(".row");
      if (!rowEl) return;
      const id = rowEl.dataset.id;
      const act = event.target.closest("[data-act]");
      if (act) { event.stopPropagation(); change(articles.find((x) => x.id === id), act.dataset.act); return; }
      location.hash = "#/a/" + encodeURIComponent(id);
    });
    $("rows").addEventListener("keydown", (event) => {
      if (event.key === "Enter" && event.target.classList.contains("row")) location.hash = "#/a/" + encodeURIComponent(event.target.dataset.id);
    });
    $("back").addEventListener("click", () => { if (history.length > 1) history.back(); else location.hash = ""; });
    $("bar-fav").addEventListener("click", () => current && change(current, "favorite"));
    $("bar-archive").addEventListener("click", () => current && change(current, "archive"));
    $("aa").addEventListener("click", () => { $("prefs").hidden = !$("prefs").hidden; });
    $("page").addEventListener("click", (event) => {
      const act = event.target.closest("[data-act]");
      if (!act || !current) return;
      const wasArchive = act.dataset.act === "archive";
      change(current, act.dataset.act);
      if (wasArchive) setTimeout(() => { if (history.length > 1) history.back(); else location.hash = ""; }, 350);
    });
    $("prefs").addEventListener("click", (event) => {
      const b = event.target.closest("[data-pref]");
      if (!b) return;
      const key = b.dataset.pref;
      if (key === "size") prefs.size = Math.min(28, Math.max(15, prefs.size + Number(b.dataset.value)));
      else prefs[key] = b.dataset.value;
      store(key, prefs[key]); applyPrefs();
    });
    document.addEventListener("click", (event) => { if (!event.target.closest("#prefs,#aa")) $("prefs").hidden = true; });
    window.addEventListener("hashchange", () => route(false));
    window.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && current) { if (!$("prefs").hidden) $("prefs").hidden = true; else $("back").click(); }
    });
    window.addEventListener("scroll", () => {
      if (!current) return;
      const max = document.documentElement.scrollHeight - innerHeight;
      $("progress").style.width = (max > 0 ? Math.min(100, (scrollY / max) * 100) : 0) + "%";
    }, { passive: true });
    // Coming back to the tab picks up what the apps have changed since.
    document.addEventListener("visibilitychange", async () => {
      if (document.visibilityState !== "visible" || !database || !loaded) return;
      try { await loadLibrary(); render(); } catch (error) { console.error(error); }
    });
    $("aa").innerHTML = svg("aa"); $("back").innerHTML = svg("back"); $("add").innerHTML = svg("plus");
    $("bar-fav").innerHTML = svg("star"); $("bar-archive").innerHTML = svg("archive");
  }

  wire();
  if (!window.POCKETME || !window.POCKETME.apiToken) { $("gate-status").textContent = "Not set up"; return; }
  connect();
})();
