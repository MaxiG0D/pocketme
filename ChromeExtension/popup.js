// Where the hosted save page lives (Web/ deployed to Cloudflare Pages). Used where PocketMe isn't installed.
const WEB_SAVE_URL = "https://maxig0d.github.io/pocketme/";

const card = document.getElementById("card");
const label = document.getElementById("label");

function show(state, text) {
  card.className = state;
  label.textContent = text;
}

async function post(tab) {
  const response = await fetch("http://127.0.0.1:47321/save", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-PocketMe": "1" },
    body: JSON.stringify({ url: tab.url, title: tab.title || "" })
  });
  return (await response.json()).saved === true;
}

async function save() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.url || !/^https?:/.test(tab.url)) return show("failed", "Can’t save this page");
  try {
    if (await post(tab)) {
      show("saved", "Saved!");
      setTimeout(() => window.close(), 1400);
    } else {
      show("failed", "Couldn’t save");
    }
  } catch (error) {
    if (!/Mac/.test(navigator.userAgent) && WEB_SAVE_URL) {
      // No PocketMe app here (Windows, Linux): the hosted save page runs inside this popup, no new tab.
      const frame = document.getElementById("web");
      frame.src = WEB_SAVE_URL + "?embed=1&url=" + encodeURIComponent(tab.url) + "&title=" + encodeURIComponent(tab.title || "");
      frame.hidden = false;
      card.hidden = true;
      document.body.classList.add("web");
      window.addEventListener("message", (event) => {
        if (event.source !== frame.contentWindow || !event.data) return;
        if (event.data.pocketme === "saved") setTimeout(() => window.close(), 1200);
      });
      return;
    }
    // PocketMe isn't running: opening the link launches it and saves the page.
    show("saving", "Opening PocketMe…");
    await chrome.tabs.create({ url: "pocketme://save?url=" + encodeURIComponent(tab.url), active: false });
    setTimeout(() => window.close(), 1800);
  }
}

card.addEventListener("click", () => { if (card.className === "failed") { show("saving", "Saving…"); save(); } });
save();
