// Media Center Watch History — Background Service Worker
// Stores the latest watch title reported by content scripts.

let latestTitle = null;

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'watch-title') {
    latestTitle = msg;
    sendResponse({ ok: true });
  } else if (msg.type === 'get-title') {
    sendResponse(latestTitle);
  }
  return true;
});

chrome.runtime.onInstalled.addListener(() => {
  console.log('Media Center Watch History extension installed');
});
