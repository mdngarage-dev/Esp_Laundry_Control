# Mesin Saya v2.1 (Flutter, Android) - banyak dryer / mesin cuci lewat BLE + order laundry (Firebase)

Butuh firmware: dryer_firmware_v3_3.ino dan washer_firmware_v1_2.ino.

## Setup dasar
1. Flutter SDK + ekstensi Flutter/Dart di VS Code, `flutter doctor`.
2. Di folder proyek: `flutter create . --org <org-sama-dengan-yang-didaftarkan-di-Firebase> --project-name <nama> --platforms android`
   (applicationId = org.nama; HARUS sama dengan package name yang didaftarkan di Firebase Console).
3. Tempel isi `docs/android_manifest_snippet.xml` ke `android/app/src/main/AndroidManifest.xml` (di dalam <manifest>, sebelum <application>).
4. Samakan versi firebase_core / cloud_firestore / firebase_auth di pubspec.yaml dengan aplikasi laundry lama (atau `flutter pub add firebase_core cloud_firestore firebase_auth`), lalu `flutter pub get`.

## Firebase (FlutterFire), TANPA login
1. Node.js terpasang, lalu: `npm install -g firebase-tools` dan `firebase login`
2. `dart pub global activate flutterfire_cli`
3. Di folder proyek: `flutterfire configure --project=<ID-project-Firebase-laundry> --platforms=android --android-package-name=<package-yang-didaftarkan>`
   Jawab YA jika diminta menimpa `lib/firebase_options.dart` (file yang ada hanya penampung sementara).
4. `google-services.json` di `android/app/`; jika error minSdk, set `minSdk = 23`.
5. Publikasikan aturan: Firebase Console > Firestore > Rules, tempel isi `docs/firestore.rules` (simpan salinan aturan lama dulu).
   Aturan baca tidak berubah dari yang lama; yang baru hanya izin update status antrian->proses untuk mesin.
6. Aplikasi > ikon palet > "Order & Firebase": uji cari nama, lalu aktifkan "Ubah status order saat mesin mulai".
