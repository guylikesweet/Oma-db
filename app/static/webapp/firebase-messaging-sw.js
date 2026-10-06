self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const data = event.notification.data || {};
  const messageId = data.chat_message_id || '';
  const url = '/webapp/' + (messageId ? '?chat_message_id=' + encodeURIComponent(messageId) : '');
  event.waitUntil(clients.matchAll({type:'window', includeUncontrolled:true}).then(function(clientList) {
    for (const client of clientList) {
      if ('focus' in client) return client.focus().then(function() {
        if (messageId && 'navigate' in client) return client.navigate(url);
      });
    }
    return clients.openWindow(url);
  }));
});

importScripts("https://www.gstatic.com/firebasejs/11.6.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/11.6.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyD-cWVrIAgXFWc0bliJpEX0VDRYwHzzJG4",
  authDomain: "",
  projectId: "omasales-5208e",
  storageBucket: "",
  messagingSenderId: "535490258779",
  appId: "1:535490258779:android:3850066aa7afcb1dd81c7e"
});
const messaging = firebase.messaging();
messaging.onBackgroundMessage(function(payload) {
  const data = payload.data || {};
  self.registration.showNotification(data.title || 'OmaSales', {
    body: data.body || '',
    icon: '/webapp/icons/Icon-192.png',
    badge: '/webapp/icons/Icon-192.png',
    data: data
  });
});
