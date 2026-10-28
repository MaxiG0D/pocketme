// The API token is meant to be public: it only allows a signed-in person to reach their own private database.
// Create it in CloudKit Dashboard > API Access > API Tokens, with the page's address as an allowed origin.
window.POCKETME = {
  container: "iCloud.com.maxigariepy.pocketme",
  environment: "development", // switch to "production" once the SaveRequest type is deployed
  apiToken: ""
};
