const api = typeof browser !== "undefined" ? browser : chrome;
const card = document.getElementById("card");
const label = document.getElementById("label");

function show(state, text) {
  card.className = state;
  label.textContent = text;
}

async function save() {
  try {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    if (!tab || !tab.url || !/^https?:/.test(tab.url)) return show("failed", "Can’t save this page");
    const reply = await api.runtime.sendNativeMessage("application.id", { url: tab.url, title: tab.title || "" });
    if (reply && reply.saved) {
      show("saved", "Saved!");
      setTimeout(() => window.close(), 1400);
    } else {
      show("failed", "Couldn’t save");
    }
  } catch (error) {
    show("failed", "Couldn’t save");
  }
}

card.addEventListener("click", () => { if (card.className === "failed") { show("saving", "Saving…"); save(); } });
save();
