# Mesin Saya (Flutter, Android) - kontrol banyak dryer / mesin cuci lewat BLE

Setup di VS Code:
1. Install Flutter SDK, ekstensi "Flutter" dan "Dart" di VS Code, lalu jalankan `flutter doctor`.
2. Di folder proyek ini jalankan:
   `flutter create . --org com.example --project-name dryer_app --platforms android`
   (membuat folder android/; simpan salinan zip ini dulu kalau ragu pubspec.yaml atau lib/ tertimpa).
3. Tempel isi `docs/android_manifest_snippet.xml` ke `android/app/src/main/AndroidManifest.xml`
   (di dalam <manifest>, sebelum <application>).
4. `flutter pub get`
5. Colok HP (USB debugging), tekan F5 atau `flutter run`. Pakai HP asli: emulator tidak punya Bluetooth.

Butuh firmware dryer v3.1 (dryer_firmware_v3_1.ino) di ESP32.
PIN default 123456. Setting disimpan di HP (draft) dan dikirim ke ESP32 lewat tombol SYNC.
