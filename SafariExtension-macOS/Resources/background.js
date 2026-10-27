const api = typeof browser !== "undefined" ? browser : chrome;

function flash(tabId, text, color) {
  api.action.setBadgeText({ tabId, text });
  if (api.action.setBadgeBackgroundColor) api.action.setBadgeBackgroundColor({ tabId, color });
  setTimeout(() => api.action.setBadgeText({ tabId, text: "" }), 1800);
}

api.action.onClicked.addListener(async (tab) => {
  if (!tab.url || !/^https?:/.test(tab.url)) return flash(tab.id, "!", "#8A8680");
  try {
    const reply = await api.runtime.sendNativeMessage("application.id", { url: tab.url, title: tab.title || "" });
    if (reply && reply.saved) flash(tab.id, "✓", "#2F8F5B");
    else flash(tab.id, "!", "#E2562B");
  } catch (error) {
    flash(tab.id, "!", "#E2562B");
  }
});
