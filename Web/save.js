const card = document.getElementById("card");
const label = document.getElementById("label");
const signIn = document.getElementById("sign-in");
const signOut = document.getElementById("sign-out");
const params = new URLSearchParams(location.search);
const link = params.get("url");
const title = params.get("title") || "";
const ZONE = "WebSaves";

function show(state, text) { card.className = state; label.textContent = text; }

function validLink(value) {
  try { return /^https?:$/.test(new URL(value).protocol); } catch { return false; }
}

async function save(database) {
  const zoneID = { zoneName: ZONE };
  const response = await database.saveRecords({
    recordType: "SaveRequest",
    zoneID,
    fields: { url: { value: link }, title: { value: title }, savedAt: { value: Date.now() } }
  });
  if (response.hasErrors) {
    const code = response.errors[0].serverErrorCode;
    // The zone is created by the app; until PocketMe has run once with this update there is nowhere to write.
    if (code === "ZONE_NOT_FOUND") return show("failed", "Open PocketMe once, then try again");
    return show("failed", "Couldn’t save");
  }
  show("saved", "Saved!");
  if (history.length <= 1) setTimeout(() => window.close(), 1400);
}

async function start() {
  if (!window.POCKETME.apiToken) return show("failed", "Not set up");
  if (!validLink(link)) return show("failed", "Can’t save this page");
  CloudKit.configure({
    containers: [{
      containerIdentifier: window.POCKETME.container,
      apiTokenAuth: { apiToken: window.POCKETME.apiToken, persist: true, signInButton: { id: "sign-in", theme: "black" }, signOutButton: { id: "sign-out", theme: "black" } },
      environment: window.POCKETME.environment
    }]
  });
  const container = CloudKit.getDefaultContainer();
  const database = container.privateCloudDatabase;
  const proceed = async (user) => {
    if (user && user.hasSignedIn !== false && user.userRecordName) {
      signIn.hidden = true;
      show("saving", "Saving…");
      try { await save(database); } catch { show("failed", "Couldn’t save"); }
    } else {
      show("saving", "Sign in to save");
      signIn.hidden = false;
    }
  };
  await proceed(await container.setUpAuth());
  container.whenUserSignsIn().then(proceed);
}

start().catch(() => show("failed", "Couldn’t save"));
