This repository contains a **single-file Flutter implementation** (`main.dart`) demonstrating how to send **critical vibration alerts** between two Android devices using **Firebase Cloud Messaging (FCM)** data messages.
The goal is to show how a device can receive a vibration alert **even in Do Not Disturb (DND) mode** without running background services.

---

## 🚀 Overview

This `main.dart` file shows how one Android device can send a **push-triggered vibration alert** to another device. The app stays completely idle in the background and wakes only when an FCM **data-only** message arrives.

Key behaviors implemented in the file:

* Registers the device with Firebase
* Saves the FCM token
* Listens for incoming data messages
* Reads the vibration pattern specified by the sender
* Vibrates the device instantly, even in **DND mode**

All communication is **event-driven**, relying entirely on push notifications—no polling or background services.

---

## ✨ Features Included in main.dart

* 📡 **FCM data-only message handling**
* 🔕 **Works even when the receiver is in DND**
* 🔋 **Zero background tasks → minimal battery usage**
* 🔐 **Token-based secure messaging**
* 🔔 **Custom vibration patterns sent by the sender**
* 🤝 **Two-way communication example (ping/pong)**

---

## 🧩 How the Logic Works

1. The device obtains an **FCM token**.
2. Token is stored in a Firebase Realtime Database path (handled inside `main.dart`).
3. When sending an alert, a device writes a message that triggers FCM delivery.
4. FCM wakes the target device.
5. The receiver reads the pattern and vibrates immediately.

The vibration pattern is **pre-planned by the sender**, making alerts intentional rather than automatic.

---

## 📡 Example Code From main.dart (Pong Response)

```dart
static Future<void> sendPongBack(String senderId) async {
  final dbRef = FirebaseDatabase.instance.ref('users');
  final snapshot = await dbRef.get();
  final users = _parseUsersSnapshot(snapshot);
  if (users.isEmpty) return;

  final senderToken = users[senderId]?['token'];
  if (senderToken == null) return;

  final myId = users.keys.firstWhere((k) => k != senderId, orElse: () => '');

  if (myId.isEmpty) return;

  await sendFcmMessage(
    targetToken: senderToken,
    data: {
      'type': 'pong',
      'sender': myId,
      'ts': nowMs(),
    },
  );
}
```

---

## 🔧 Firebase Required

Although only `main.dart` is provided, the functionality depends on:

* `google-services.json` (Android)
* A valid Firebase project
* A generated `firebase_options.dart` (via `flutterfire configure`)

Without these files, FCM and Realtime Database will not function.

---

## 📌 Notes

* Some OEM devices (Xiaomi/Oppo/Vivo) may require battery optimization to be disabled for more consistent FCM delivery.
* The app vibrates **only when triggered intentionally** by sender-defined patterns.
* No automatic background tasks, workers, or periodic timers are used.

---

## 📄 License

Unlicense

---
