// Stride service worker: shows reminder notifications and opens the app when one is tapped.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Stride', {
    body: d.body || 'Time to study.',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    tag: d.tag || 'stride-daily',   // replaces the previous reminder instead of stacking
    renotify: true,
    requireInteraction: d.stage === 3,
    data: { url: '/' },
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) if ('focus' in c) return c.focus();
    return self.clients.openWindow('/');
  }));
});

// A fetch handler keeps the app installable on Android.
self.addEventListener('fetch', () => {});
