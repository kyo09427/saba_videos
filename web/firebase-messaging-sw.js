importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyC_Ts8ZMzY7Mv4OME42PtsZEulhPJ-2snE",
  appId: "1:54119387843:web:a1fcfeec245732dae94876",
  messagingSenderId: "54119387843",
  projectId: "sabatube",
  authDomain: "sabatube.firebaseapp.com",
  storageBucket: "sabatube.firebasestorage.app",
});

const messaging = firebase.messaging();

// バックグラウンド通知の受信処理
messaging.onBackgroundMessage((payload) => {
  const { title, body, icon } = payload.notification ?? {};
  self.registration.showNotification(title ?? "", {
    body: body ?? "",
    icon: icon ?? "/icons/Icon-192.png",
  });
});
