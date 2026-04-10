// Media Center Watch History — Content Script
// Runs on streaming sites, detects what's playing, and reports to the local updater service.

function getService() {
  const h = location.hostname;
  if (h.includes('netflix'))     return { brand: 'netflix',  name: 'Netflix' };
  if (h.includes('youtube'))     return { brand: 'youtube',  name: 'YouTube' };
  if (h.includes('disneyplus'))  return { brand: 'disney',   name: 'Disney+' };
  if (h.includes('max.com'))     return { brand: 'max',      name: 'Max' };
  if (h.includes('primevideo'))  return { brand: 'prime',    name: 'Prime Video' };
  if (h.includes('spotify'))     return { brand: 'spotify',  name: 'Spotify' };
  if (h.includes('twitch'))      return { brand: 'twitch',   name: 'Twitch' };
  if (h.includes('plex'))        return { brand: 'plex',     name: 'Plex' };
  return null;
}

function extractTitle() {
  const service = getService();
  if (!service) return null;

  let title = null;

  switch (service.brand) {
    case 'netflix':
      title = document.querySelector('[data-uia="video-title"]')?.textContent
           || document.querySelector('.video-title')?.textContent;
      break;
    case 'youtube':
      title = document.querySelector('#movie_player .ytp-title-link')?.textContent
           || document.querySelector('h1.ytd-watch-metadata yt-formatted-string')?.textContent
           || document.querySelector('.title.ytd-video-primary-info-renderer')?.textContent;
      break;
    case 'disney':
      title = document.querySelector('[data-testid="content-title"]')?.textContent;
      break;
    case 'prime':
      title = document.querySelector('.atvwebplayersdk-title-text')?.textContent
           || document.querySelector('[data-automation-id="title"]')?.textContent;
      break;
    case 'spotify':
      title = document.querySelector('[data-testid="nowplaying-track-link"]')?.textContent;
      break;
    case 'twitch':
      title = document.querySelector('[data-a-target="stream-title"]')?.textContent;
      break;
    case 'plex':
      title = document.querySelector('[class*="MetadataPosterTitle"] a')?.textContent;
      break;
  }

  // Fallback: extract from document.title by stripping service suffix
  if (!title) {
    const raw = document.title;
    const cleaned = raw
      .replace(/\s*[-–|]\s*Netflix$/i, '')
      .replace(/\s*[-–|]\s*YouTube$/i, '')
      .replace(/\s*[-–|]\s*Disney\+$/i, '')
      .replace(/\s*[-–|]\s*Max$/i, '')
      .replace(/\s*[-–|]\s*Prime Video$/i, '')
      .replace(/\s*[-–|]\s*Spotify$/i, '')
      .replace(/\s*[-–|]\s*Twitch$/i, '')
      .replace(/\s*[-–|]\s*Plex$/i, '')
      .trim();
    if (cleaned && cleaned !== raw.trim() && cleaned.length >= 2) {
      title = cleaned;
    }
  }

  return title ? title.trim() : null;
}

let lastTitle = null;
let lastReport = 0;

function reportTitle() {
  const service = getService();
  if (!service) return;

  const title = extractTitle();
  const now = Date.now();

  // Throttle: only report if title changed or 30s elapsed
  if (title === lastTitle && now - lastReport < 30000) return;
  lastTitle = title;
  lastReport = now;

  // Send to local updater service
  fetch('http://127.0.0.1:8765/watch-title', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      brand: service.brand,
      name: service.name,
      title: title,
      url: location.href,
      timestamp: now
    })
  }).catch(() => {});
}

// Poll every 5 seconds
setInterval(reportTitle, 5000);

// Also fire on visibility change and initial load
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') reportTitle();
});
setTimeout(reportTitle, 2000);
