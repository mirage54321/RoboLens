

self.addEventListener('push', function (event) {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
  }
  const title = data.title || 'Match starting soon';
  const options = {
    body: data.body || '',
    icon: data.icon || 'icons/Icon-111.png',
    badge: data.badge || 'icons/Icon-111.png',
    data: { url: data.url || '/' },
    tag: data.tag,
    renotify: Boolean(data.renotify),
  };
  if (Array.isArray(data.vibrate)) {
    options.vibrate = data.vibrate;
  }
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(event.notification.data.url || '/');
      }
    })
  );
});