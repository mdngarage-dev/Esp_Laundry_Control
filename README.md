# ESP Laundry Control (Washer & Dryer Controller)

Sistem kontrol terpadu berbasis **ESP32** dan aplikasi **Flutter** untuk mengoperasikan mesin cuci (*washer*) dan mesin pengering (*dryer*) komersial/laundry. Satu desain papan PCB tunggal (`PCB1`, ukuran `150 × 141 mm`) mendukung dua konfigurasi perangkat keras dan firmware sekaligus.

---

## 📁 Struktur Repository

```text
esp-laundry-control/
├── app/                              # Aplikasi kontrol & monitoring (Flutter: Android, iOS, Web)
├── firmware/                         # Kode sumber mikrokontroler ESP32 (Arduino IDE)
│   ├── dryer_firmware_v3_1/          # Firmware khusus mesin pengering (Dryer)
│   └── washer_firmware_v1/           # Firmware khusus mesin cuci (Washer)
├── hardware/                         # Desain sirkuit & daftar komponen PCB1
│   ├── BOM_PCB.xlsx                  # Bill of Materials (111 komponen total)
│   └── Gerber_PCB.zip                # File produksi PCB (150 x 141 mm)
├── docs/                             # Dokumentasi teknis & perakitan
│   └── Panduan_Instalasi_PCB.pdf     # Panduan instalasi, wiring, dan pengujian
├── .gitignore                        # Daftar file sementara yang diabaikan Git
└── README.md                         # Dokumentasi utama proyek
```

---

## ⚙️ Perbandingan Konfigurasi Hardware (`PCB1`)

Satu PCB yang sama dapat dirakit untuk dua jenis mesin dengan perbedaan konfigurasi komponen berikut:

| Fitur / Bagian | `[D]` Mesin Pengering (*Dryer*) | `[W]` Mesin Cuci (*Washer*) |
| :--- | :--- | :--- |
| **Motor Utama** | Motor drum AC via Relay `RLY2` (`CN2`) | Motor BLDC 3-fasa via IPM `U1` (`U21`) & Hall (`CN10`) |
| **Sistem Pemanas / Air** | Gas LPG: Katup (`CN4`), Igniter (`CN5`), NTC (`CN6`) | Katup isi (`CN3`), Pompa buang (`CN2`), Level (`CN14`), Sabun (`CN5`) |
| **Sensor Pintu** | Saklar mekanis pasif 2 kabel (`CN12`) | Kunci pintu PTC 220V (`CN4`) + kontak terkunci (`CN12`) |
| **Panel Kontrol** | `CN9`: OLED, Rotary Encoder (Knob), Tombol Start/Stop | Sama (`CN9`) |
| **Bridge `D6` & Isolasi** | **Tidak dipasang** (GND terisolasi via HLK-10M15) | **Dipasang** (`GND` terhubung ke negatif bus DC 310V) |
| **Jumlah Komponen** | **75 dari 111** komponen dipasang (36 dikosongkan) | **Semua 111** komponen dipasang |

---

## 🔌 Daftar Pin & Soket Utama

* **Soket Hijau (Sekrup 5,08 mm):** Tegangan tinggi `220 VAC` (`CN1`–`CN5`).
* **Soket Putih (XH Berkunci):** Tegangan rendah & sensor (`CN6`, `CN9`, `CN10`, `CN12`, `CN14`, `CN15`).
* **Bus Netral (`N`):** Terminal `CN2`–`CN5` hanya memutus/menyambung jalur fasa (`L`). Semua kabel netral beban digabung menggunakan terminal eksternal (WAGO 5 lubang) dari `CN1` pin 2.

| Soket | Label PCB | Fungsi `[D]` Dryer | Fungsi `[W]` Mesin Cuci |
| :--- | :--- | :--- | :--- |
| **CN1** | `AC IN 220V` | Listrik masuk (`1 = L`, `2 = N`) | Listrik masuk (`1 = L`, `2 = N`) |
| **CN2** | `RLY2` | Motor drum AC | Pompa buang (*drain pump*) |
| **CN3** | `RLY1` | Cadangan | Katup isi air (*inlet valve* via sakelar level pin A) |
| **CN4** | `RLY3` | Katup gas (seri *thermal fuse* & *high-limit*) | Aktuator kunci pintu PTC 220 VAC |
| **CN5** | `RLY4` | Igniter pemantik gas | Pompa sabun otomatis 220 VAC |
| **CN6** | `NTC1` | Sensor suhu saluran buang (`10 kΩ`, B≈3950) | Sensor suhu air panas (opsional) |
| **CN9** | `PANEL` | Modul OLED, Rotary Knob, Tombol Start/Stop | Modul OLED, Rotary Knob, Tombol Start/Stop |
| **CN10** | `HALL` | *Tidak dipasang* | Sensor Hall motor BLDC (`5V, GND, A, B, C`) |
| **CN12** | `PINTU` | Saklar pintu mekanis 2 kabel | Kontak konfirmasi pintu terkunci |
| **CN14** | `LEVEL` | *Tidak dipasang* | Sakelar level air 3 pin (`COM, A, B`) |
| **U21** | `MOTOR` | *Tidak dipasang* | Output 3-fasa motor BLDC (`U, V, W`) |

---

## ⚠️ Peringatan Keselamatan Penting

1. **Tegangan Tinggi Mematikan:** Sistem bekerja pada tegangan **220 VAC** dan bus DC sekitar **310 VDC** (pada versi mesin cuci).
2. **Ground Non-Terisolasi pada Versi Mesin Cuci:** Karena `Bridge D6` terpasang pada versi `[W]`, jalur `GND` papan terhubung langsung ke listrik jala-jala. **Dilarang menyentuh papan, soket panel, atau mencolokkan kabel USB ke komputer saat steker listrik terpasang.**
3. **Kapasitor Bus (`U10`):** Cabut steker dan tunggu minimal **3 menit** sebelum menyentuh PCB versi mesin cuci setelah daya dimatikan.
4. **Pengaman Wajib:** Selalu gunakan **MCB & ELCB**, sambungkan kabel `PE` (ground) langsung ke bodi logam mesin (bukan ke PCB), dan gunakan **lampu bohlam 100–200 W seri** pada jalur `L` saat pengujian pertama.
5. **Proteksi Kelembapan:** Semprot PCB dengan *conformal coating* bening (hindari bagian dalam soket) setelah seluruh pengujian lulus.

---

## 🚀 Cara Menjalankan Aplikasi (`app/`)

1. Masuk ke direktori aplikasi:
   ```bash
   cd app
   ```
2. Unduh seluruh dependensi Flutter:
   ```bash
   flutter pub get
   ```
3. Jalankan aplikasi di Chrome atau perangkat Android:
   ```bash
   flutter run -d chrome
   ```

---

## 📖 Dokumentasi Lengkap
Untuk urutan penyolderan komponen, identifikasi kabel kunci pintu 3/4 pin, kalibrasi tegangan *buck converter* `U29` (5,0 V), serta prosedur pengujian bertahap, silakan baca dokumen lengkap di [`docs/Panduan_Instalasi_PCB.pdf`](docs/Panduan_Instalasi_PCB.pdf).
