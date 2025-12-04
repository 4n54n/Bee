Below is a **clean, professional, and complete README** for your project, including installation steps, technical explanation, and instructions to update the Firebase configuration file.

---

# 📱 Critical Vibration Alert App

*A Flutter-based Android application for sending intentional vibration alerts between two devices—even in Do Not Disturb mode.*

---

## 🚀 Overview

This app enables one Android device to send a **critical vibration alert** to another device, even when the receiver is in **Do Not Disturb (DND)** mode. Both devices must have the app installed.

Communication is handled using **Firebase Realtime Database** and **Firebase Cloud Messaging (FCM) data-only messages**.
The application does **not** run background services or background polling. Instead, it remains completely idle until an incoming FCM push message wakes it. When the message is received, the app vibrates using a **pre-planned vibration pattern determined by the sender**, ensuring meaningful, intentional alerts.

---

## ✨ Features

* 📡 **Push-based communication** using FCM data messages
* 🔕 **Works in Do Not Disturb mode**
* 🔋 **No background tasks** → low battery usage
* 📱 **Two-way communication** (ping/pong style)
* 🔐 **Uses secure Firebase token-based messaging**
* 🔔 **Custom, pre-planned vibration patterns** chosen by the sender
* ⚡ **Fast and reliable delivery** through Google Play Services

---

## 🧩 How It Works

1. Each device registers with Firebase and saves its FCM token to Firebase Realtime Database.
2. When Device A wants to alert Device B, it sends a **data-only FCM message**.
3. Android wakes Device B’s app momentarily to process the message.
4. Device B reads the vibration pattern (pre-planned by the sender) and triggers the vibration.
5. No continuous background service is used — only event-driven push delivery.

---

## 📁 Project Structure (Brief)

```
lib/
 ├── main.dart
 ├── firebase_messaging_handler.dart
 ├── vibration_service.dart
 ├── database_service.dart
 └── utils/
```

---

## 🔧 Installation & Setup

### 1️⃣ **Clone the repository**

```sh
git clone https://github.com/your-username/critical-vibration-alert.git
cd critical-vibration-alert
```

### 2️⃣ **Install dependencies**

```sh
flutter pub get
```

### 3️⃣ **Configure Firebase (IMPORTANT)**

This project requires **your own Firebase project**.

You MUST update both Firebase configuration files:

#### **For Android:**

Replace files in:

```
android/app/google-services.json
```

with the one downloaded from your Firebase project.

#### **For Flutter (Dart):**

Also update:

```
lib/firebase_options.dart
```

You can auto-generate this file by running:

```sh
flutterfire configure
```

> ⚠️ Without updating these two files, FCM and Realtime Database will **not** work.

---

## ▶️ Running the App

```sh
flutter run
```

Install the app on **two devices** and test sending alerts.

---

## 🛠 Technologies Used

* **Flutter**
* **Firebase Realtime Database**
* **Firebase Cloud Messaging (FCM)**
* **Android Vibrator API**

---

## 📡 Example: Sending a "Pong" Response

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

## 📌 Notes

* Some OEM devices (Xiaomi, Vivo, Oppo) may require disabling battery optimization for reliable FCM delivery.
* The app triggers vibration **only through intentional, pre-planned patterns chosen by the sender**.
* No automatic pattern generation or background polling is used.

---

## 📄 License

Unlicense
