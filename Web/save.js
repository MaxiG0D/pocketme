const card = document.getElementById("card");
const label = document.getElementById("label");
const signIn = document.getElementById("sign-in-wrap");
const detailEl = document.getElementById("detail");
const signOut = document.getElementById("sign-out");
const params = new URLSearchParams(location.search);
const link = params.get("url");
const title = params.get("title") || "";
const ZONE = "WebSaves";
// Inside the Chrome extension's popup the page is a compact frame that tells the popup when it is done.
if (params.get("embed")) document.body.classList.add("embed");
const tell = (state) => { if (params.get("embed")) parent.postMessage({ pocketme: state }, "*"); };

function show(state, text, detail) {
  card.className = state;
  tell(state);
  label.textContent = text;
  detailEl.textContent = detail || "";
}

// A short reason under a failure, so a broken setup can be told apart from a broken save.
function reason(error) {
  console.error(error);
  return String((error && (error.ckErrorCode || error.serverErrorCode || error.message)) || error).slice(0, 80);
}

function validLink(value) {
  try { return /^https?:$/.test(new URL(value).protocol); } catch { return false; }
}

async function save(database) {
  const zoneID = { zoneName: ZONE };
  // CloudKit JS reads the zone from the options argument; a zoneID on the record itself is ignored and
  // lands the record in the default zone, where the app never looks.
  const response = await database.saveRecords({
    recordType: "SaveRequest",
    fields: { url: { value: link }, title: { value: title }, savedAt: { value: Date.now() } }
  }, { zoneID });
  if (response.hasErrors) {
    const code = response.errors[0].serverErrorCode;
    // The zone is created by the app; until PocketMe has run once with this update there is nowhere to write.
    if (code === "ZONE_NOT_FOUND") return show("failed", "Open PocketMe once, then try again");
    return show("failed", "Couldn’t save", reason(response.errors[0].serverErrorCode + " " + (response.errors[0].reason || "")));
  }
  const saved = response.records && response.records[0];
  // A record that came back without an id was not stored, whatever hasErrors says.
  if (!saved || !saved.recordName || saved.serverErrorCode) {
    return show("failed", "Couldn’t save", reason(JSON.stringify(saved || response).slice(0, 160)));
  }
  const zone = saved.zoneID && saved.zoneID.zoneName;
  const who = saved.created && saved.created.userRecordName;
  show("saved", "Saved!", `${saved.recordName.slice(0, 8)} · ${zone || "?"} · ${(who || "").slice(-6)}`);
  if (!params.get("embed") && history.length <= 1) setTimeout(() => window.close(), 1400);
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
      try { await save(database); } catch (error) { show("failed", "Couldn’t save", reason(error)); }
    } else {
      show("idle", "Sign in to save");
      signIn.hidden = false;
    }
  };
  await proceed(await container.setUpAuth());
  container.whenUserSignsIn().then(proceed);
}

start().catch((error) => show("failed", "Couldn’t save", reason(error)));
