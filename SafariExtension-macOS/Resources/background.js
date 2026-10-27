const api = typeof browser !== "undefined" ? browser : chrome;
const sizes = [48, 96, 128, 256];
const paths = (name) => Object.fromEntries(sizes.map((size) => [size, `icon-${name}${name ? "-" : ""}${size}.png`]));
const icons = { default: paths(""), saved: paths("saved"), error: paths("error") };
const resetTimers = new Map();

function show(tabId, state, title, duration) {
  clearTimeout(resetTimers.get(tabId));
  api.action.setTitle({ tabId, title });
  api.action.setIcon({ tabId, path: icons[state] });
  resetTimers.set(tabId, setTimeout(() => {
    api.action.setTitle({ tabId, title: "Save to PocketMe" });
    api.action.setIcon({ tabId, path: icons.default });
    resetTimers.delete(tabId);
  }, duration));
}

api.action.onClicked.addListener(async (tab) => {
  const failure = () => show(tab.id, "error", "Couldn’t save — click to retry", 3000);
  if (!tab.url || !/^https?:/.test(tab.url)) return failure();
  api.action.setBadgeText({ tabId: tab.id, text: "" });
  api.action.setTitle({ tabId: tab.id, title: "Saving to PocketMe…" });
  try {
    const reply = await api.runtime.sendNativeMessage("application.id", { url: tab.url, title: tab.title || "" });
    if (reply && reply.saved) show(tab.id, "saved", "Saved to PocketMe", 1500);
    else failure();
  } catch (error) {
    failure();
  }
});
