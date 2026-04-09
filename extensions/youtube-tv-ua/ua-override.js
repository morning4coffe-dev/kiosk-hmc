// Override navigator.userAgent on youtube.com so client-side JS checks also
// see the TV user-agent (the declarativeNetRequest rule only covers HTTP headers).
Object.defineProperty(navigator, 'userAgent', {
  get: () => 'Mozilla/5.0 (Linux; Android 11; BRAVIA 4K UR2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.145 Mobile Safari/537.36',
  configurable: false
});
