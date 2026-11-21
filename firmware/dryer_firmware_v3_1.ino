/*
 * Firmware Mesin Dryer (Gas) v3 - ESP32 DevKit V1 - PCB1 (OLED I2C + knob + Start) + BLE untuk aplikasi Android
 *
 * PlatformIO:
 *   lib_deps = adafruit/Adafruit SSD1306, adafruit/Adafruit GFX Library
 *   build_flags = -DCORE_DEBUG_LEVEL=0          ; GPIO1 (TX0) dipakai sensor pintu, log harus mati
 *   board_build.partitions = huge_app.csv       ; library BLE besar
 *   (Preferences dan BLE sudah bawaan core ESP32)
 *
 * ALUR PENGGUNAAN DI MESIN
 *  OFF -> putar knob 1 klik (kanan = EXTRA DRY, kiri = 30 MINS) -> mesin ON, layar menampilkan pilihan.
 *  Putar terus untuk ganti program. TEKAN knob (atau Start) -> mesin jalan, layar hitung mundur.
 *  Selesai -> bunyi selesai -> OFF sendiri.
 *  Saat jalan:  tekan singkat = JEDA / LANJUT
 *               tahan 2 detik = STOP (gas mati, motor tetap putar mendinginkan, lalu OFF)
 *               tahan 5 detik = MATI DARURAT (semua relay mati seketika)
 *  Pintu dibuka saat jalan -> semua dijeda, buzzer peringatan terus bunyi sampai pintu ditutup.
 *    Setelah ditutup: lanjut otomatis (door_resume=1) atau menunggu tombol (door_resume=0). Diatur dari aplikasi.
 *  Mode uji hardware: tahan knob saat power-on (relay satu per satu, tanpa interlock, LEPAS BEBAN dulu).
 *
 * PENGAMAN HARDWARE (thermal fuse + high-limit seri dengan katup gas) TIDAK BOLEH dilepas.
 *
 * ===================== PROTOKOL BLE (kompatibel Nordic UART) =====================
 * Nama perangkat : DRYER-ESP32
 * Service        : 6e400001-b5a3-f393-e0a9-e50e24dcca9e
 * RX (app TULIS) : 6e400002-b5a3-f393-e0a9-e50e24dcca9e   satu perintah teks per write, spasi atau koma pemisah
 * TX (NOTIFY)    : 6e400003-b5a3-f393-e0a9-e50e24dcca9e   satu baris teks per notifikasi
 * WAJIB: app memanggil requestMtu(185) setelah connect (MTU default 23 memotong baris jadi 20 byte).
 *
 * PERINTAH (kecuali yang bertanda *, semua butuh AUTH dulu setiap koneksi):
 *   AUTH <pin>                   PIN default 123456. 5x salah = terkunci 60 detik
 *  *GET                          kirim versi, semua setting, semua program, dan status
 *  *STOP                         berjalan -> STOP + pendinginan; layar pilihan/error/selesai -> OFF
 *  *EMERG                        mati darurat seketika
 *   SEL <1..9>                   pilih program (1=30 MINS,2=1 JAM,3=2 JAM,4=2,5 JAM,5=AIRING,6=JEANS,7=IRON DRY,8=TOWELS,9=EXTRA DRY)
 *                                kalau mesin OFF, mesin ON dulu
 *   START                        hanya jika setting remote_start=1 (default 0), pintu harus tertutup
 *   PAUSE / RESUME               jeda / lanjut
 *   SET <kunci> <nilai>          ubah setting (di RAM). Hanya saat mesin tidak berjalan. Ditolak jika di luar batas aman
 *   PSET <1..9> <menit> <heat0/1> <onS> <offS> <tCut> <coolS>   ubah satu program
 *   CALREF <suhu_referensi_C>    kalibrasi offset NTC: offset = referensi - suhu mentah
 *   SAVE                         simpan ke flash (SYNC). Tanpa SAVE, perubahan hilang saat restart
 *   LOAD                         buang perubahan yang belum disimpan
 *   DEFAULTS                     kembali ke nilai pabrik (PIN dan nama tetap) lalu simpan
 *   RING <p1..p9>                urutan program di knob (permutasi 1..9). Putar kanan dari OFF = p1, lalu p2, ...; putar kiri dari OFF = p9
 *   NAME <teks>                  nama mesin (1-23 karakter ASCII, tanpa koma), tersimpan permanen setelah SAVE
 * Balasan: "OK,<perintah>" atau "ERR,<perintah>,<alasan>"
 *
 * NOTIFIKASI DARI ESP:
 *   S,<state>,<prog>,<sisaDetik>,<totalDetik>,<suhu*10>,<suhuMentah*10>,<ohmNTC>,<heat>,<gas>,<igniter>,<motor>,<pintuTertutup>,<fault>,<sensorOK>,<pendinginanAkhir>,<retry>,<belumDisimpan>
 *     state: 0 OFF,1 PILIH,2 JALAN,3 JEDA MANUAL,4 JEDA PINTU,5 STOP-PENDINGINAN,6 SELESAI,7 ERROR
 *     heat : 0 mati,1 igniter memanas,2 pembakaran,3 purge/coba lagi
 *     dikirim tiap 1 detik dan saat state berubah
 *   C,<kunci>,<nilai>            satu setting (balasan GET)
 *   P,<idx>,<nama>,<menit>,<heat>,<onS>,<offS>,<tCut>,<coolS>   satu program (balasan GET)
 *   V,<versi>,<tipe: DRYER>
 *   N,<nama mesin>
 *   R,<p1..p9>                   urutan knob; baris R adalah PENUTUP dump GET
 *   E,DONE | E,DOOR_OPEN | E,FAULT,<kode>
 *
 * KUNCI SET: door_resume(0/1) remote_start(0/1) retry(0-3) ign_off_proof(0/1) stopcool_t(30-60) ign_warm(20-90 s)
 *   prestart(5-60 s) proof(15-60 s) purge(30-300 s) stopcool_s(30-600 s) pin(0-999999) ntc_off(-15..15 C)
 *   ntc_beta(2500-4500) t_hard(50-90 C) hyst(2-20 C) proof_rise(0.5-10 C)
 * Aturan: tCut + 5 <= t_hard, tCut - hyst >= 30, onS 30-900, offS 10-900, menit 5-240.
 *
 * Kalibrasi 2 titik: baca ohmNTC di dua suhu referensi (T1,R1) (T2,R2), hitung di app:
 *   beta = ln(R1/R2) / (1/T1 - 1/T2)   (T dalam Kelvin) -> SET ntc_beta, lalu CALREF di suhu referensi.
 */
#include <Arduino.h>
#include <Wire.h>
#include <stdarg.h>
#include <strings.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <esp_task_wdt.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#if __has_include(<BLE2902.h>)
#include <BLE2902.h>
#define HAS_BLE2902 1
#endif

#define FW_VERSION "3.1"
#define MACHINE_TYPE "DRYER"
#define ENC_REVERSE 0         // ganti 1 kalau putar kanan malah ke 30 MINS
#define ENC_STEPS_PER_DETENT 4
#define OLED_ADDR 0x3C
#define DOOR_DEBOUNCE_MS 150
#define CFG_MAGIC 0xD17E0310UL   // struct berubah di v3.1: setting lama di flash otomatis reset ke default

// ===================== PIN (netlist PCB1) =====================
const uint8_t PIN_RELAY_SPARE = 12;   // RLY1 CN3 (tidak dipakai)
const uint8_t PIN_RELAY_MOTOR = 14;   // RLY2 CN2 motor drum
const uint8_t PIN_RELAY_GAS   = 27;   // RLY3 CN4 katup gas
const uint8_t PIN_RELAY_IGN   = 26;   // RLY4 CN5 igniter
const uint8_t PIN_BUZZER = 19;
const uint8_t PIN_ENC_CLK = 4, PIN_ENC_DT = 5, PIN_ENC_SW = 25;   // pull-up eksternal ada
const uint8_t PIN_START = 2;          // pull-up internal (disarankan tambah pull-up eksternal)
const uint8_t PIN_NTC = 33;           // NTC1: pull-up 10k ke 3V3 (R44), ADC1 aman dengan BLE
const uint8_t PIN_DOOR = 1;           // TX0: opto U4, LOW = pintu tertutup
const uint8_t PIN_SDA = 23, PIN_SCL = 18;

// ===================== PARAMETER TETAP =====================
const float    NTC_R0 = 10000.0f, VREF_MV = 3300.0f;
const uint32_t SELECT_IDLE_MS = 60000UL, DONE_SHOW_MS = 8000UL;
const uint32_t DOOR_RESUME_MS = 2000UL, PAUSE_TIMEOUT_MS = 600000UL, FAULT_COOL_MS = 300000UL;
const uint32_t HOLD_STOP_MS = 2000UL, HOLD_EMERG_MS = 5000UL, HOLD_OFF_SELECT_MS = 1500UL;

// ===================== KONFIGURASI (disimpan di flash/NVS) =====================
// minutes = durasi total (termasuk pendinginan akhir). heat 0 = hanya angin.
// onS/offS = siklus gas. tCut = suhu buang gas dipotong. coolS = pendinginan akhir maksimal.
struct ProgCfg { uint16_t minutes; uint8_t heat; uint16_t onS; uint16_t offS; uint8_t tCut; uint16_t coolS; };
const char* const PNAMES[9] = {"30 MINS", "1 JAM", "2 JAM", "2,5 JAM", "AIRING", "JEANS", "IRON DRY", "TOWELS", "EXTRA DRY"};
const ProgCfg DEF_PROGS[9] = {
  {30,  1, 240,  90, 68, 300},
  {60,  1, 240,  90, 68, 480},
  {120, 1, 240,  90, 68, 480},
  {150, 1, 240,  90, 68, 480},
  {30,  0,   0,   0,  0,   0},   // AIRING: angin saja
  {60,  1, 330,  60, 70, 360},   // JEANS: lebih panas
  {60,  1, 420,  45, 72, 180},   // IRON DRY: panas maksimal
  {30,  1,  90, 150, 60, 480},   // TOWELS: gas sebentar
  {65,  1, 240,  90, 68, 480}};  // EXTRA DRY
const uint8_t RING_N = 10;       // cincin knob: 0 = OFF, 1..9 = program

struct Cfg {
  uint32_t magic;
  uint8_t doorAutoResume, remoteStart, maxRetry, ignOffAfterProof, stopCoolTemp;
  uint16_t ignWarmS, prestartS, proofS, purgeS, stopCoolS;
  uint32_t pin;
  float ntcOffset, ntcBeta, tHard, hyst, proofRise;
  ProgCfg prog[9];
  uint8_t ring[9];      // urutan program di knob: putar kanan dari OFF = ring[0], lalu ring[1], ... ; putar kiri dari OFF = ring[8]
  char name[24];        // nama mesin (diatur dari aplikasi)
};
Cfg cfg;
bool cfgDirty = false;

enum PT : uint8_t { PT_U8, PT_U16, PT_U32, PT_F };
struct Param { const char* key; PT t; void* p; float lo, hi; };
const Param PARAMS[] = {
  {"door_resume",   PT_U8,  &cfg.doorAutoResume,  0, 1},
  {"remote_start",  PT_U8,  &cfg.remoteStart,     0, 1},
  {"retry",         PT_U8,  &cfg.maxRetry,        0, 3},
  {"ign_off_proof", PT_U8,  &cfg.ignOffAfterProof, 0, 1},
  {"stopcool_t",    PT_U8,  &cfg.stopCoolTemp,    30, 60},
  {"ign_warm",      PT_U16, &cfg.ignWarmS,        20, 90},
  {"prestart",      PT_U16, &cfg.prestartS,       5, 60},
  {"proof",         PT_U16, &cfg.proofS,          15, 60},
  {"purge",         PT_U16, &cfg.purgeS,          30, 300},
  {"stopcool_s",    PT_U16, &cfg.stopCoolS,       30, 600},
  {"pin",           PT_U32, &cfg.pin,             0, 999999},
  {"ntc_off",       PT_F,   &cfg.ntcOffset,       -15, 15},
  {"ntc_beta",      PT_F,   &cfg.ntcBeta,         2500, 4500},
  {"t_hard",        PT_F,   &cfg.tHard,           50, 90},
  {"hyst",          PT_F,   &cfg.hyst,            2, 20},
  {"proof_rise",    PT_F,   &cfg.proofRise,       0.5f, 10}};

float getParamVal(const Param& q) {
  switch (q.t) {
    case PT_U8:  return *(uint8_t*)q.p;
    case PT_U16: return *(uint16_t*)q.p;
    case PT_U32: return (float)*(uint32_t*)q.p;
    default:     return *(float*)q.p;
  }
}
void putParamVal(const Param& q, float v) {
  switch (q.t) {
    case PT_U8:  *(uint8_t*)q.p = (uint8_t)(v + 0.5f); break;
    case PT_U16: *(uint16_t*)q.p = (uint16_t)(v + 0.5f); break;
    case PT_U32: *(uint32_t*)q.p = (uint32_t)(v + 0.5f); break;
    default:     *(float*)q.p = v; break;
  }
}
const Param* findParam(const char* k) { for (const Param& q : PARAMS) if (!strcasecmp(q.key, k)) return &q; return nullptr; }

void cfgDefaults() {
  memset(&cfg, 0, sizeof(cfg));
  cfg.magic = CFG_MAGIC; cfg.doorAutoResume = 1; cfg.remoteStart = 0; cfg.maxRetry = 1; cfg.ignOffAfterProof = 0; cfg.stopCoolTemp = 45;
  cfg.ignWarmS = 40; cfg.prestartS = 10; cfg.proofS = 40; cfg.purgeS = 60; cfg.stopCoolS = 180; cfg.pin = 123456;
  cfg.ntcOffset = 0; cfg.ntcBeta = 3950; cfg.tHard = 80; cfg.hyst = 7; cfg.proofRise = 2;
  memcpy(cfg.prog, DEF_PROGS, sizeof(DEF_PROGS));
  const uint8_t defRing[9] = {9, 8, 7, 6, 5, 4, 3, 2, 1};   // EXTRA DRY, TOWELS, IRON DRY, JEANS, AIRING, 2,5 JAM, 2 JAM, 1 JAM, 30 MINS
  memcpy(cfg.ring, defRing, 9);
  strncpy(cfg.name, "Dryer", 23);
}
bool cfgSane() {                                    // batas aman: dipakai untuk menolak nilai dari aplikasi
  for (const Param& q : PARAMS) { float v = getParamVal(q); if (v < q.lo || v > q.hi) return false; }
  for (int i = 0; i < 9; i++) {
    const ProgCfg& p = cfg.prog[i];
    if (p.minutes < 5 || p.minutes > 240 || p.heat > 1) return false;
    if (p.heat) {
      if (p.onS < 30 || p.onS > 900 || p.offS < 10 || p.offS > 900 || p.coolS > 900) return false;
      if (p.tCut < 40 || (float)p.tCut + 5.0f > cfg.tHard || (float)p.tCut - cfg.hyst < 30.0f) return false;
    }
  }
  if (cfg.name[23] != 0 || cfg.name[0] == 0) return false;
  for (int k = 0; cfg.name[k]; k++) if ((uint8_t)cfg.name[k] < 0x20 || (uint8_t)cfg.name[k] > 0x7E) return false;
  uint16_t seen = 0;
  for (int k = 0; k < 9; k++) { uint8_t v = cfg.ring[k]; if (v < 1 || v > 9) return false; seen |= (uint16_t)(1u << v); }
  if (seen != 0x3FE) return false;                      // ring harus permutasi 1..9
  return true;
}
Preferences prefs;
void cfgLoad() {
  cfgDefaults();
  prefs.begin("dryer", true);
  if (prefs.getBytesLength("cfg") == sizeof(Cfg)) {
    Cfg t; prefs.getBytes("cfg", &t, sizeof(Cfg));
    if (t.magic == CFG_MAGIC) { Cfg keep = cfg; cfg = t; if (!cfgSane()) cfg = keep; }
  }
  prefs.end();
  cfgDirty = false;
}
bool cfgSave() {
  prefs.begin("dryer", false);
  size_t n = prefs.putBytes("cfg", &cfg, sizeof(Cfg));
  prefs.end();
  return n == sizeof(Cfg);
}

// ===================== BUZZER =====================
struct Seg { uint16_t on, off; };
const Seg P_TICK[]   = {{12, 0}};
const Seg P_PRESS[]  = {{120, 0}};
const Seg P_START[]  = {{100, 80}, {100, 0}};
const Seg P_POWERON[]= {{60, 60}, {60, 60}, {60, 0}};
const Seg P_DONE[]   = {{400, 200}, {400, 200}, {700, 0}};
const Seg P_STOP[]   = {{600, 0}};
const Seg P_EMERG[]  = {{400, 150}, {400, 0}};
const Seg P_FAULT[]  = {{80, 80}, {80, 80}, {80, 80}, {80, 80}, {80, 80}, {80, 0}};
const Seg P_WARN[]   = {{250, 250}};            // diulang terus saat pintu terbuka
const Seg P_NO[]     = {{60, 60}, {60, 0}};
const Seg* bz = nullptr; uint8_t bzN = 0, bzI = 0; bool bzOn = false, bzLoop = false; uint32_t bzT = 0;
#define BEEP(p) beepPattern(p, sizeof(p) / sizeof(Seg), false)
void beepPattern(const Seg* p, uint8_t n, bool loop) { bz = p; bzN = n; bzI = 0; bzLoop = loop; bzOn = true; bzT = millis(); digitalWrite(PIN_BUZZER, HIGH); }
void beepStop() { bz = nullptr; bzLoop = false; digitalWrite(PIN_BUZZER, LOW); }
void buzzerTick(uint32_t now) {
  if (!bz) return;
  const Seg& s = bz[bzI];
  if (bzOn && now - bzT >= s.on) { digitalWrite(PIN_BUZZER, LOW); bzOn = false; bzT = now; if (s.off == 0 && bzI == bzN - 1 && !bzLoop) bz = nullptr; }
  else if (!bzOn && now - bzT >= s.off) {
    if (++bzI >= bzN) { if (bzLoop) bzI = 0; else { bz = nullptr; return; } }
    bzOn = true; bzT = now; digitalWrite(PIN_BUZZER, HIGH);
  }
}

// ===================== STATE =====================
enum St : uint8_t { S_OFF, S_SELECT, S_RUN, S_PAUSE_MAN, S_PAUSE_DOOR, S_STOPCOOL, S_DONE, S_FAULT };
enum Heat : uint8_t { H_OFF, H_WARM, H_BURN, H_PURGE };
Adafruit_SSD1306 oled(128, 64, &Wire, -1);
St st = S_OFF; Heat heat = H_OFF;
uint8_t ringIdx = 9, lastRing = 9; uint8_t faultCode = 0;
uint32_t totalMs = 0, runMs = 0, lastTick = 0, motorOnAt = 0, heatT = 0, heatOffAt = 0, burnStart = 0, stateT = 0, idleT = 0, doorClosedAt = 0, stopEnd = 0;
bool motorOn = false, gasOn = false, ignOn = false, proven = false, oledOn = false;
uint8_t retries = 0; float tExh = 25.0f, tRaw = 25.0f, ntcOhm = 0, tMin = 0; bool sensorOk = false; uint8_t badReads = 0;
uint32_t lastLowMs = 0; bool doorClosed = false;

const ProgCfg& prog() { return cfg.prog[(ringIdx ? ringIdx : 1) - 1]; }
const char* progName() { return PNAMES[(ringIdx ? ringIdx : 1) - 1]; }
uint32_t coolMsNow() { const ProgCfg& p = prog(); uint32_t q = totalMs / 4, c = (uint32_t)p.coolS * 1000UL; return q < c ? q : c; }
bool idleState() { return st == S_OFF || st == S_SELECT || st == S_DONE || st == S_FAULT; }   // setting boleh diubah
// posisi knob: 0 = OFF, 1..9 = program cfg.ring[pos-1]
uint8_t posOfProg(uint8_t prog) { if (!prog) return 0; for (uint8_t k = 0; k < 9; k++) if (cfg.ring[k] == prog) return k + 1; return 0; }
uint8_t progAtPos(uint8_t pos) { return pos ? cfg.ring[pos - 1] : 0; }

// ===================== ANTRIAN BLE (TX) =====================
#define TXQ_N 40
#define TX_LEN 88
BLECharacteristic* txChar = nullptr;
volatile bool bleConn = false, authed = false;
char txq[TXQ_N][TX_LEN]; uint8_t txHead = 0, txTail = 0; uint32_t txLast = 0;
void txPush(const char* fmt, ...) {
  if (!bleConn) return;
  uint8_t nx = (txHead + 1) % TXQ_N; if (nx == txTail) return;     // penuh: baris dibuang
  va_list ap; va_start(ap, fmt); vsnprintf(txq[txHead], TX_LEN, fmt, ap); va_end(ap);
  txHead = nx;
}
void txPump(uint32_t now) {
  if (txHead == txTail) return;
  if (!bleConn || !txChar) { txTail = txHead; return; }
  if (now - txLast < 30) return;
  txLast = now;
  txChar->setValue((uint8_t*)txq[txTail], strlen(txq[txTail])); txChar->notify();
  txTail = (txTail + 1) % TXQ_N;
}

// ===================== OUTPUT =====================
void setMotor(bool on) { motorOn = on; digitalWrite(PIN_RELAY_MOTOR, on); if (on) motorOnAt = millis(); }
void setIgn(bool on) { ignOn = on; digitalWrite(PIN_RELAY_IGN, on); }
void setGas(bool on) { if (on && !(motorOn && doorClosed && sensorOk)) on = false; gasOn = on; digitalWrite(PIN_RELAY_GAS, on); }   // interlock
void heatStop() { setGas(false); setIgn(false); heat = H_OFF; heatOffAt = millis(); proven = false; }
void allOff() { setGas(false); setIgn(false); setMotor(false); heat = H_OFF; digitalWrite(PIN_RELAY_SPARE, LOW); }

// ===================== SENSOR =====================
void readNtc() {
  uint32_t s = 0; for (int i = 0; i < 16; i++) s += analogReadMilliVolts(PIN_NTC);
  float mv = s / 16.0f;
  if (mv < 80.0f || mv > 3150.0f) { if (++badReads >= 4) sensorOk = false; return; }
  badReads = 0;
  float r = NTC_R0 * mv / (VREF_MV - mv);
  ntcOhm = r;
  float t = 1.0f / (1.0f / 298.15f + log(r / NTC_R0) / cfg.ntcBeta) - 273.15f;
  tRaw = sensorOk ? (tRaw * 0.7f + t * 0.3f) : t; sensorOk = true;
  tExh = tRaw + cfg.ntcOffset;                       // tRaw = suhu mentah, tExh = suhu terkalibrasi
}
void doorSample(uint32_t now) {
  if (digitalRead(PIN_DOOR) == LOW) lastLowMs = now;
  doorClosed = (now - lastLowMs) < DOOR_DEBOUNCE_MS;
}

// ===================== DISPLAY =====================
void oledPower(bool on) { if (on == oledOn) return; oledOn = on; oled.ssd1306_command(on ? SSD1306_DISPLAYON : SSD1306_DISPLAYOFF); }
void txt(int x, int y, uint8_t size, const char* s, bool center = false) {
  oled.setTextSize(size); int w = strlen(s) * 6 * size; if (center) x = (128 - w) / 2;
  oled.setCursor(x < 0 ? 0 : x, y); oled.print(s);
}
void fmtTime(char* b, uint32_t sec, bool& big) {
  if (sec >= 3600) { sprintf(b, "%lu:%02lu:%02lu", (unsigned long)(sec / 3600), (unsigned long)((sec / 60) % 60), (unsigned long)(sec % 60)); big = false; }
  else { sprintf(b, "%02lu:%02lu", (unsigned long)(sec / 60), (unsigned long)(sec % 60)); big = true; }
}
void drawHold(uint32_t held) {
  if (held < 300) return;
  int w = held >= HOLD_STOP_MS ? (int)(128UL * (held - HOLD_STOP_MS) / (HOLD_EMERG_MS - HOLD_STOP_MS)) : (int)(128UL * held / HOLD_STOP_MS);
  oled.fillRect(0, 56, 128, 8, SSD1306_BLACK); oled.drawRect(0, 56, 128, 8, SSD1306_WHITE); oled.fillRect(0, 56, w > 128 ? 128 : w, 8, SSD1306_WHITE);
}
const char* heatText() {
  if (!prog().heat) return "ANGIN (TANPA GAS)";
  if (runMs + coolMsNow() >= totalMs) return "PENDINGINAN";
  switch (heat) { case H_WARM: return "IGNITER MEMANAS"; case H_BURN: return gasOn ? "GAS NYALA" : "GAS MATI"; case H_PURGE: return "COBA LAGI"; default: return "GAS MATI"; }
}
void drawUI(uint32_t now, uint32_t held) {
  char b[24]; bool big;
  oled.clearDisplay(); oled.setTextColor(SSD1306_WHITE);
  static bool lastInv = false;
  bool inv = (st == S_PAUSE_DOOR && !doorClosed && ((now / 400) & 1));
  if (inv != lastInv) { oled.invertDisplay(inv); lastInv = inv; }
  switch (st) {
    case S_OFF: break;
    case S_SELECT:
      txt(0, 0, 1, "PILIH PROGRAM", true);
      if (bleConn) oled.fillCircle(124, 3, 2, SSD1306_WHITE);
      if (ringIdx == 0) { txt(0, 22, 3, "OFF", true); txt(0, 56, 1, "TEKAN = MATI", true); }
      else {
        txt(0, 16, 2, progName(), true);
        if (prog().minutes >= 60) sprintf(b, "%u JAM %02u MENIT", prog().minutes / 60, prog().minutes % 60); else sprintf(b, "%u MENIT", prog().minutes);
        txt(0, 38, 1, b, true); txt(0, 56, 1, "TEKAN = MULAI", true);
      }
      break;
    case S_RUN: case S_PAUSE_MAN: case S_PAUSE_DOOR: {
      txt(0, 0, 1, progName());
      if (bleConn) oled.fillCircle(90, 3, 2, SSD1306_WHITE);
      if (sensorOk) { sprintf(b, "%dC", (int)(tExh + 0.5f)); txt(128 - strlen(b) * 6, 0, 1, b); }
      uint32_t rem = totalMs > runMs ? (totalMs - runMs + 999) / 1000 : 0; fmtTime(b, rem, big);
      txt(0, 16, big ? 3 : 2, b, true);
      if (st == S_PAUSE_DOOR) {
        if (!doorClosed) txt(0, 46, 1, "PINTU TERBUKA! TUTUP", true);
        else if (cfg.doorAutoResume) txt(0, 46, 1, "MELANJUTKAN...", true);
        else txt(0, 46, 1, "PINTU OK - TEKAN LANJUT", true);
      }
      else if (st == S_PAUSE_MAN) txt(0, 46, 1, "JEDA - TEKAN LANJUT", true);
      else txt(0, 46, 1, heatText(), true);
      if (held > 0) drawHold(held); else { oled.drawRect(0, 58, 128, 5, SSD1306_WHITE); oled.fillRect(0, 58, (int)(128UL * runMs / (totalMs ? totalMs : 1)), 5, SSD1306_WHITE); }
      break; }
    case S_STOPCOOL: txt(0, 6, 2, "STOP", true); txt(0, 30, 1, "PENDINGINAN...", true); sprintf(b, "%dC  TEKAN = OFF", (int)(tExh + 0.5f)); txt(0, 50, 1, b, true); break;
    case S_DONE: txt(0, 14, 2, "SELESAI", true); txt(0, 40, 1, "MESIN OFF...", true); break;
    case S_FAULT: sprintf(b, "ERROR E%u", faultCode); txt(0, 8, 2, b, true);
      txt(0, 34, 1, faultCode == 1 ? "SENSOR SUHU RUSAK" : faultCode == 2 ? "SUHU TERLALU PANAS" : "API TIDAK NYALA", true); txt(0, 52, 1, "TEKAN = OFF", true); break;
  }
  oled.display();
}

// ===================== TRANSISI =====================
void goOff() { allOff(); beepStop(); st = S_OFF; oledPower(false); }
void emergencyOff() { allOff(); beepStop(); BEEP(P_EMERG); st = S_OFF; oledPower(false); }
void powerOn(uint32_t now) { st = S_SELECT; idleT = now; oledPower(true); }
void doFault(uint8_t code) { heatStop(); faultCode = code; st = S_FAULT; stopEnd = millis() + FAULT_COOL_MS; BEEP(P_FAULT); txPush("E,FAULT,%u", code); }
bool startRun(uint32_t now) {
  if (!doorClosed) { BEEP(P_NO); return false; }
  if (prog().heat && !sensorOk) { BEEP(P_NO); return false; }
  totalMs = (uint32_t)prog().minutes * 60000UL; runMs = 0; lastTick = now; retries = 0; lastRing = ringIdx;
  heatStop(); heatOffAt = now - (uint32_t)prog().offS * 1000UL; setMotor(true); st = S_RUN; BEEP(P_START);
  return true;
}
void pauseRun(St why, uint32_t now) {
  heatStop(); setMotor(false); st = why; stateT = now;
  if (why == S_PAUSE_DOOR) { beepPattern(P_WARN, 1, true); txPush("E,DOOR_OPEN"); } else BEEP(P_PRESS);
}
void resumeRun(uint32_t now) { heatStop(); heatOffAt = now - (uint32_t)prog().offS * 1000UL; setMotor(true); lastTick = now; st = S_RUN; beepStop(); BEEP(P_PRESS); }
void stopAndCool(uint32_t now) {
  heatStop(); BEEP(P_STOP);
  if (prog().heat && sensorOk && tExh > cfg.stopCoolTemp && doorClosed) { st = S_STOPCOOL; stopEnd = now + (uint32_t)cfg.stopCoolS * 1000UL; setMotor(true); }
  else goOff();
}
void finishRun(uint32_t now) { heatStop(); setMotor(false); st = S_DONE; stateT = now; beepStop(); BEEP(P_DONE); txPush("E,DONE"); }
void ignitionFail(uint32_t now) { setGas(false); setIgn(false); proven = false; if (++retries > cfg.maxRetry) { doFault(3); return; } heat = H_PURGE; heatT = now; }

// ===================== KONTROL GAS =====================
void heatTick(uint32_t now) {
  if (st != S_RUN) { if (heat != H_OFF || gasOn || ignOn) heatStop(); return; }
  const ProgCfg& p = prog();
  if (sensorOk && tExh >= cfg.tHard) { doFault(2); return; }
  if (!p.heat) return;
  if (!sensorOk) { doFault(1); return; }
  bool allowed = doorClosed && motorOn && (now - motorOnAt >= (uint32_t)cfg.prestartS * 1000UL) && (runMs + coolMsNow() < totalMs);
  if (!allowed) { if (heat != H_OFF || gasOn || ignOn) heatStop(); return; }
  float tOff = p.tCut, tOn = p.tCut - cfg.hyst; uint32_t onMs = (uint32_t)p.onS * 1000UL, offMs = (uint32_t)p.offS * 1000UL;
  switch (heat) {
    case H_OFF:
      if (now - heatOffAt >= offMs && tExh <= tOn) { setIgn(true); heat = H_WARM; heatT = now; }
      break;
    case H_WARM:
      if (tExh >= tOff) { heatStop(); break; }
      if (now - heatT >= (uint32_t)cfg.ignWarmS * 1000UL) { setGas(true); if (!gasOn) { heatStop(); break; } heat = H_BURN; heatT = now; proven = false; tMin = tExh; }
      break;
    case H_BURN:
      if (tExh >= tOff) { heatStop(); break; }
      if (!proven) {
        if (tExh < tMin) tMin = tExh;
        if (tExh - tMin >= cfg.proofRise) { proven = true; retries = 0; burnStart = now; if (cfg.ignOffAfterProof) setIgn(false); }
        else if (now - heatT > (uint32_t)cfg.proofS * 1000UL) ignitionFail(now);
      } else if (now - burnStart >= onMs) heatStop();       // akhir periode nyala -> periode mati
      break;
    case H_PURGE:
      if (now - heatT >= (uint32_t)cfg.purgeS * 1000UL) { heat = H_OFF; heatOffAt = now - offMs; }
      break;
  }
}

// ===================== INPUT =====================
int8_t encRead() {
  static const int8_t T[16] = {0,-1,1,0, 1,0,0,-1, -1,0,0,1, 0,1,-1,0};
  static uint8_t prev = 0; static int8_t acc = 0;
  uint8_t cur = (digitalRead(PIN_ENC_CLK) << 1) | digitalRead(PIN_ENC_DT);
  acc += T[(prev << 2) | cur]; prev = cur;
  if (acc >= ENC_STEPS_PER_DETENT)  { acc = 0; return ENC_REVERSE ? -1 :  1; }
  if (acc <= -ENC_STEPS_PER_DETENT) { acc = 0; return ENC_REVERSE ?  1 : -1; }
  return 0;
}
void onTurn(int8_t d, uint32_t now) {            // d>0 = kanan (searah jarum jam), d<0 = kiri
  if (st == S_OFF) { ringIdx = d > 0 ? progAtPos(1) : progAtPos(RING_N - 1); powerOn(now); BEEP(P_POWERON); return; }
  if (st == S_SELECT) { uint8_t pos = (posOfProg(ringIdx) + RING_N + (d > 0 ? 1 : -1)) % RING_N; ringIdx = progAtPos(pos); idleT = now; BEEP(P_TICK); }
}
void onShortPress(uint32_t now) {
  switch (st) {
    case S_OFF: ringIdx = lastRing; powerOn(now); BEEP(P_POWERON); break;
    case S_SELECT: idleT = now; if (ringIdx == 0) { BEEP(P_PRESS); goOff(); } else startRun(now); break;
    case S_RUN: pauseRun(S_PAUSE_MAN, now); break;
    case S_PAUSE_MAN: case S_PAUSE_DOOR: if (doorClosed) resumeRun(now); else BEEP(P_NO); break;
    case S_STOPCOOL: case S_FAULT: BEEP(P_PRESS); goOff(); break;
    default: break;
  }
}
bool btnDown = false, stopFired = false, emergFired = false; uint32_t btnAt = 0, btnLast = 0;
void buttonTick(uint32_t now) {
  bool p = (digitalRead(PIN_ENC_SW) == LOW) || (digitalRead(PIN_START) == LOW);
  if (p && !btnDown && now - btnLast > 30) { btnDown = true; btnAt = now; stopFired = emergFired = false; }
  else if (btnDown) {
    uint32_t held = now - btnAt;
    bool running = (st == S_RUN || st == S_PAUSE_MAN || st == S_PAUSE_DOOR);
    if (running && !stopFired && held >= HOLD_STOP_MS) { stopFired = true; stopAndCool(now); }
    if (st != S_OFF && (st == S_STOPCOOL || running || stopFired) && !emergFired && held >= HOLD_EMERG_MS) { emergFired = true; emergencyOff(); }
    if (st == S_SELECT && !stopFired && held >= HOLD_OFF_SELECT_MS) { stopFired = true; BEEP(P_PRESS); goOff(); }
    if (!p) {
      btnDown = false; btnLast = now;
      if (!stopFired && !emergFired && held >= 30) onShortPress(now);
    }
  }
}

// ===================== APLIKASI ANDROID (BLE) =====================
#define SVC_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define RX_UUID  "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define TX_UUID  "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define RXQ_N 6
#define RX_LEN 80
char rxq[RXQ_N][RX_LEN]; volatile uint8_t rxHead = 0, rxTail = 0; portMUX_TYPE rxMux = portMUX_INITIALIZER_UNLOCKED;
volatile bool needAdv = false; volatile uint32_t advAt = 0;

class RxCb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    uint8_t* d = c->getData(); size_t n = c->getLength();
    if (!d || n == 0) return;
    portENTER_CRITICAL(&rxMux);
    uint8_t nx = (rxHead + 1) % RXQ_N;
    if (nx != rxTail) { size_t m = n < RX_LEN - 1 ? n : RX_LEN - 1; memcpy(rxq[rxHead], d, m); rxq[rxHead][m] = 0; rxHead = nx; }
    portEXIT_CRITICAL(&rxMux);
  }
};
class SrvCb : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { bleConn = true; authed = false; }
  void onDisconnect(BLEServer*) override { bleConn = false; authed = false; needAdv = true; advAt = millis(); }
};
bool rxPop(char* out) {
  bool ok = false;
  portENTER_CRITICAL(&rxMux);
  if (rxHead != rxTail) { memcpy(out, rxq[rxTail], RX_LEN); rxTail = (rxTail + 1) % RXQ_N; ok = true; }
  portEXIT_CRITICAL(&rxMux);
  return ok;
}

void sendStatus() {
  bool runningS = (st == S_RUN || st == S_PAUSE_MAN || st == S_PAUSE_DOOR);
  uint32_t rem = (runningS && totalMs > runMs) ? (totalMs - runMs + 999) / 1000 : 0;
  bool cool = (st == S_RUN && prog().heat && runMs + coolMsNow() >= totalMs);
  txPush("S,%u,%u,%lu,%lu,%d,%d,%d,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u",
         (unsigned)st, (unsigned)ringIdx, (unsigned long)rem, (unsigned long)(totalMs / 1000),
         (int)lroundf(tExh * 10.0f), (int)lroundf(tRaw * 10.0f), (int)ntcOhm,
         (unsigned)heat, (unsigned)gasOn, (unsigned)ignOn, (unsigned)motorOn, (unsigned)doorClosed,
         (unsigned)faultCode, (unsigned)sensorOk, (unsigned)cool, (unsigned)retries, (unsigned)cfgDirty);
}
void sendCfg() {
  txPush("V,%s,%s", FW_VERSION, MACHINE_TYPE);
  for (const Param& q : PARAMS) {
    if (!strcmp(q.key, "pin")) continue;                       // PIN tidak pernah dikirim
    if (q.t == PT_F) txPush("C,%s,%.2f", q.key, getParamVal(q)); else txPush("C,%s,%ld", q.key, (long)getParamVal(q));
  }
  for (int i = 0; i < 9; i++) {
    const ProgCfg& p = cfg.prog[i];
    txPush("P,%d,%s,%u,%u,%u,%u,%u,%u", i + 1, PNAMES[i], (unsigned)p.minutes, (unsigned)p.heat, (unsigned)p.onS, (unsigned)p.offS, (unsigned)p.tCut, (unsigned)p.coolS);
  }
  txPush("N,%s", cfg.name);
  txPush("R,%u,%u,%u,%u,%u,%u,%u,%u,%u", cfg.ring[0], cfg.ring[1], cfg.ring[2], cfg.ring[3], cfg.ring[4], cfg.ring[5], cfg.ring[6], cfg.ring[7], cfg.ring[8]);   // R = akhir dump setting
  sendStatus();
}
void ok(const char* c) { txPush("OK,%s", c); }
void er(const char* c, const char* why) { txPush("ERR,%s,%s", c, why); }

void handleCmd(char* line, uint32_t now) {
  char* sp = nullptr;
  char* cmd = strtok_r(line, " ,\r\n", &sp);
  if (!cmd) return;
  for (char* c = cmd; *c; c++) *c = toupper((unsigned char)*c);
  char* tok[12]; int n = 0;
  while (n < 12 && (tok[n] = strtok_r(nullptr, " ,\r\n", &sp))) n++;
  bool running = (st == S_RUN || st == S_PAUSE_MAN || st == S_PAUSE_DOOR);

  // ---- perintah aman: tanpa AUTH ----
  if (!strcmp(cmd, "EMERG")) { emergencyOff(); ok(cmd); return; }
  if (!strcmp(cmd, "STOP")) {
    if (running) stopAndCool(now);
    else if (st == S_SELECT || st == S_STOPCOOL || st == S_FAULT || st == S_DONE) { BEEP(P_PRESS); goOff(); }
    ok(cmd); return;
  }
  if (!strcmp(cmd, "GET")) { sendCfg(); return; }
  if (!strcmp(cmd, "AUTH")) {
    static uint8_t fails = 0; static uint32_t lockUntil = 0;
    if (lockUntil && now < lockUntil) { er(cmd, "locked"); return; }
    if (n >= 1 && (uint32_t)strtoul(tok[0], nullptr, 10) == cfg.pin) { authed = true; fails = 0; ok(cmd); }
    else { if (++fails >= 5) { fails = 0; lockUntil = now + 60000UL; } er(cmd, "pin"); }
    return;
  }
  if (!authed) { er(cmd, "auth"); return; }

  // ---- perintah terotorisasi ----
  if (!strcmp(cmd, "SEL")) {
    int a = n ? atoi(tok[0]) : 0;
    if (a < 1 || a > 9) { er(cmd, "arg"); return; }
    if (st == S_OFF) { ringIdx = a; powerOn(now); BEEP(P_POWERON); ok(cmd); }
    else if (st == S_SELECT) { ringIdx = a; idleT = now; BEEP(P_TICK); ok(cmd); }
    else er(cmd, "busy");
    return;
  }
  if (!strcmp(cmd, "START")) {
    if (!cfg.remoteStart) { er(cmd, "remote_start_off"); return; }
    if (st != S_SELECT || ringIdx == 0) { er(cmd, "not_selected"); return; }
    if (startRun(now)) ok(cmd); else er(cmd, "door_or_sensor");
    return;
  }
  if (!strcmp(cmd, "PAUSE")) { if (st == S_RUN) { pauseRun(S_PAUSE_MAN, now); ok(cmd); } else er(cmd, "state"); return; }
  if (!strcmp(cmd, "RESUME")) {
    if ((st == S_PAUSE_MAN || st == S_PAUSE_DOOR) && doorClosed) { resumeRun(now); ok(cmd); } else er(cmd, "state_or_door");
    return;
  }
  if (!strcmp(cmd, "SET")) {
    if (n < 2) { er(cmd, "arg"); return; }
    if (!idleState()) { er(cmd, "busy"); return; }
    const Param* q = findParam(tok[0]);
    if (!q) { er(cmd, "key"); return; }
    float v = atof(tok[1]);
    if (v < q->lo || v > q->hi) { er(cmd, "range"); return; }
    float old = getParamVal(*q); putParamVal(*q, v);
    if (!cfgSane()) { putParamVal(*q, old); er(cmd, "constraint"); return; }
    cfgDirty = true; if (!strcasecmp(q->key, "ntc_off") || !strcasecmp(q->key, "ntc_beta")) readNtc();
    ok(cmd); return;
  }
  if (!strcmp(cmd, "PSET")) {
    if (n < 7) { er(cmd, "arg"); return; }
    if (!idleState()) { er(cmd, "busy"); return; }
    int i = atoi(tok[0]); if (i < 1 || i > 9) { er(cmd, "arg"); return; }
    long v[6]; for (int k = 0; k < 6; k++) v[k] = atol(tok[k + 1]);
    if (v[0] < 0 || v[0] > 65535 || v[1] < 0 || v[1] > 1 || v[2] < 0 || v[2] > 65535 || v[3] < 0 || v[3] > 65535 || v[4] < 0 || v[4] > 255 || v[5] < 0 || v[5] > 65535) { er(cmd, "range"); return; }
    ProgCfg old = cfg.prog[i - 1]; ProgCfg& p = cfg.prog[i - 1];
    p.minutes = v[0]; p.heat = v[1]; p.onS = v[2]; p.offS = v[3]; p.tCut = v[4]; p.coolS = v[5];
    if (!cfgSane()) { cfg.prog[i - 1] = old; er(cmd, "constraint"); return; }
    cfgDirty = true; ok(cmd); return;
  }
  if (!strcmp(cmd, "RING")) {
    if (n < 9) { er(cmd, "arg"); return; }
    if (!idleState()) { er(cmd, "busy"); return; }
    uint8_t old[9]; memcpy(old, cfg.ring, 9);
    for (int k = 0; k < 9; k++) cfg.ring[k] = (uint8_t)atoi(tok[k]);
    if (!cfgSane()) { memcpy(cfg.ring, old, 9); er(cmd, "constraint"); return; }
    cfgDirty = true; ok(cmd); return;
  }
  if (!strcmp(cmd, "NAME")) {
    if (n < 1) { er(cmd, "arg"); return; }
    if (!idleState()) { er(cmd, "busy"); return; }
    char nm[24]; nm[0] = 0;
    for (int k = 0; k < n; k++) { if (k && strlen(nm) < 23) strcat(nm, " "); strncat(nm, tok[k], 23 - strlen(nm)); }
    char old[24]; memcpy(old, cfg.name, 24); memset(cfg.name, 0, 24); strncpy(cfg.name, nm, 23);
    if (!cfgSane()) { memcpy(cfg.name, old, 24); er(cmd, "constraint"); return; }
    cfgDirty = true; ok(cmd); return;
  }
  if (!strcmp(cmd, "CALREF")) {
    if (n < 1) { er(cmd, "arg"); return; }
    if (!idleState()) { er(cmd, "busy"); return; }
    if (!sensorOk) { er(cmd, "sensor"); return; }
    float off = atof(tok[0]) - tRaw;
    if (off < -15.0f || off > 15.0f) { er(cmd, "range"); return; }
    cfg.ntcOffset = off; tExh = tRaw + off; cfgDirty = true; ok(cmd); return;
  }
  if (!strcmp(cmd, "SAVE")) {
    if (!idleState()) { er(cmd, "busy"); return; }
    if (cfgSave()) { cfgDirty = false; ok(cmd); } else er(cmd, "flash");
    return;
  }
  if (!strcmp(cmd, "LOAD")) { if (!idleState()) { er(cmd, "busy"); return; } cfgLoad(); readNtc(); ok(cmd); return; }
  if (!strcmp(cmd, "DEFAULTS")) {
    if (!idleState()) { er(cmd, "busy"); return; }
    uint32_t pin = cfg.pin; char nm[24]; memcpy(nm, cfg.name, 24); cfgDefaults(); cfg.pin = pin; memcpy(cfg.name, nm, 24); cfgSave(); cfgDirty = false; readNtc(); ok(cmd); return;
  }
  er(cmd, "cmd");
}

BLEServer* bleSrv = nullptr;
void bleInit() {
  BLEDevice::init(cfg.name);                       // nama BLE = nama mesin (berlaku setelah restart)
  BLEDevice::setMTU(185);
  bleSrv = BLEDevice::createServer(); bleSrv->setCallbacks(new SrvCb());
  BLEService* svc = bleSrv->createService(SVC_UUID);
  txChar = svc->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
#ifdef HAS_BLE2902
  txChar->addDescriptor(new BLE2902());
#endif
  BLECharacteristic* rx = svc->createCharacteristic(RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new RxCb());
  svc->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SVC_UUID); adv->setScanResponse(true);
  BLEDevice::startAdvertising();
}
void bleTick(uint32_t now) {
  char line[RX_LEN];
  while (rxPop(line)) handleCmd(line, now);
  if (needAdv && now - advAt > 300) { needAdv = false; BLEDevice::startAdvertising(); }
  static uint32_t tS = 0; static uint8_t lastSt = 255;
  if (bleConn && ((uint8_t)st != lastSt || now - tS >= 1000)) { tS = now; sendStatus(); }
  lastSt = (uint8_t)st;
  txPump(now);
}

// ===================== MODE UJI HARDWARE (tahan knob saat power-on) =====================
void runTestMode() {
  const char* names[5] = {"RLY1 CN3", "RLY2 MOTOR", "RLY3 GAS", "RLY4 IGN", "BUZZER"};
  const uint8_t pins[5] = {PIN_RELAY_SPARE, PIN_RELAY_MOTOR, PIN_RELAY_GAS, PIN_RELAY_IGN, PIN_BUZZER};
  bool on[5] = {false, false, false, false, false};
  uint8_t sel = 0; bool prevUp = false; char b[28];
  uint32_t t0 = millis(), tUi = 0, tNtc = 0, tDoor = 0, lastBtn = 0;
  oledPower(true);
  while (true) {
    uint32_t now = millis(); esp_task_wdt_reset();
    if (now - tDoor >= 2) { tDoor = now; doorSample(now); }
    if (now - tNtc >= 500) { tNtc = now; readNtc(); }
    int8_t d = encRead();
    if (d) { sel = (sel + 5 + (d > 0 ? 1 : -1)) % 5; t0 = now; }
    bool up = digitalRead(PIN_ENC_SW) == HIGH && digitalRead(PIN_START) == HIGH;
    if (!up && prevUp && now - lastBtn > 200) { lastBtn = now; on[sel] = !on[sel]; digitalWrite(pins[sel], on[sel]); t0 = now; }
    prevUp = up;
    if (now - t0 > 300000UL) { for (int i = 0; i < 5; i++) digitalWrite(pins[i], LOW); ESP.restart(); }
    if (now - tUi >= 150) {
      tUi = now; oled.clearDisplay(); oled.setTextColor(SSD1306_WHITE);
      txt(0, 0, 1, "MODE UJI - LEPAS BEBAN");
      sprintf(b, "> %s: %s", names[sel], on[sel] ? "ON" : "OFF"); txt(0, 14, 1, b);
      sprintf(b, "NTC %d.%dC %s", (int)tExh, (int)(fabsf(tExh) * 10) % 10, sensorOk ? "OK" : "RUSAK"); txt(0, 28, 1, b);
      sprintf(b, "MENTAH %dC %dohm", (int)tRaw, (int)ntcOhm); txt(0, 40, 1, b);
      sprintf(b, "PINTU: %s", doorClosed ? "TERTUTUP" : "TERBUKA"); txt(0, 52, 1, b);
      oled.display();
    }
  }
}

// ===================== SETUP & LOOP =====================
void setup() {
  const uint8_t outs[] = {PIN_RELAY_SPARE, PIN_RELAY_MOTOR, PIN_RELAY_GAS, PIN_RELAY_IGN, PIN_BUZZER};
  for (uint8_t i = 0; i < sizeof(outs); i++) { pinMode(outs[i], OUTPUT); digitalWrite(outs[i], LOW); }
  pinMode(PIN_ENC_CLK, INPUT_PULLUP); pinMode(PIN_ENC_DT, INPUT_PULLUP); pinMode(PIN_ENC_SW, INPUT_PULLUP); pinMode(PIN_START, INPUT_PULLUP);
  pinMode(PIN_DOOR, INPUT);                       // GPIO1: Serial TIDAK dipakai
  analogSetPinAttenuation(PIN_NTC, ADC_11db);
  cfgLoad();
  lastRing = ringIdx = cfg.ring[0];
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  esp_task_wdt_config_t wc = {8000, 0, true}; esp_task_wdt_reconfigure(&wc);
#else
  esp_task_wdt_init(8, true);
#endif
  esp_task_wdt_add(NULL);
  Wire.begin(PIN_SDA, PIN_SCL); Wire.setClock(400000);
  oled.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR); oled.clearDisplay(); oled.display(); oledOn = true; oledPower(false);
  for (int i = 0; i < 6; i++) { readNtc(); delay(20); }
  lastLowMs = millis() - 1000;
  if (digitalRead(PIN_ENC_SW) == LOW) runTestMode();     // tidak kembali
  bleInit();
}

void loop() {
  uint32_t now = millis(); esp_task_wdt_reset();
  static uint32_t tNtc = 0, tUi = 0, tDoor = 0; static bool lastDoor = false;
  if (now - tDoor >= 2) { tDoor = now; doorSample(now); }
  if (now - tNtc >= 500) { tNtc = now; readNtc(); }

  if (st == S_RUN) {                                           // waktu berjalan hanya saat RUN
    runMs += now - lastTick; lastTick = now;
    if (runMs >= totalMs) finishRun(now);
  }
  if (st == S_RUN && !doorClosed) pauseRun(S_PAUSE_DOOR, now);
  if (st == S_PAUSE_DOOR) {
    if (doorClosed) {
      if (bzLoop) beepStop();                                  // pintu sudah ditutup: warning berhenti
      if (!lastDoor) doorClosedAt = now;
      if (cfg.doorAutoResume && now - doorClosedAt >= DOOR_RESUME_MS) resumeRun(now);
    } else if (!bz) beepPattern(P_WARN, 1, true);              // pintu (masih/kembali) terbuka: warning terus
    if (st == S_PAUSE_DOOR && now - stateT > PAUSE_TIMEOUT_MS) goOff();
  }
  if (st == S_PAUSE_MAN && now - stateT > PAUSE_TIMEOUT_MS) goOff();
  lastDoor = doorClosed;
  if (st == S_STOPCOOL) {
    if (!doorClosed) goOff();
    else if (now >= stopEnd || (sensorOk && tExh <= cfg.stopCoolTemp)) goOff();
  }
  if (st == S_FAULT) {
    static uint32_t tFb = 0; if (now - tFb > 10000UL) { tFb = now; BEEP(P_FAULT); }
    setGas(false);
    if (motorOn && (now >= stopEnd || !doorClosed || (sensorOk && tExh <= cfg.stopCoolTemp))) setMotor(false);
  }
  if (st == S_DONE && now - stateT >= DONE_SHOW_MS) goOff();
  if (st == S_SELECT && now - idleT >= SELECT_IDLE_MS) { BEEP(P_PRESS); goOff(); }
  if (gasOn && !(motorOn && doorClosed && sensorOk)) heatStop();   // pengaman umum
  heatTick(now);

  int8_t d = encRead(); if (d) onTurn(d, now);
  buttonTick(now);
  bleTick(now);
  buzzerTick(now);
  if (now - tUi >= 150) { tUi = now; if (st != S_OFF) drawUI(now, (btnDown && (st == S_RUN || st == S_PAUSE_MAN || st == S_PAUSE_DOOR)) ? now - btnAt : 0); }
}
