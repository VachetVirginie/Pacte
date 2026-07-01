const BUILD_VERSION = "2026-07-01T18:10:51.178Z";

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  const payload = event.data?.json() ?? {
    title: "Pacte",
    body: "La bande compte sur toi aujourd’hui 👀"
  };
  event.waitUntil(self.registration.showNotification(payload.title, {
    body: payload.body,
    icon: "/icon.svg",
    badge: "/icon.svg",
    data: payload.url ?? "/",
    vibrate: [120, 50, 120]
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data || "/"));
});
