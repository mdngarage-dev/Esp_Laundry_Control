/*
 * Firmware Mesin Cuci v1 - ESP32 DevKit V1 - PCB1 (versi mesin cuci) + BLE untuk aplikasi Android
 *
 * PlatformIO:
 *   lib_deps = adafruit/Adafruit SSD1306, adafruit/Adafruit GFX Library
 *   build_flags = -DCORE_DEBUG_LEVEL=0          ; GPIO1 (TX0) dan GPIO3 (RX0) dipakai sensor, log harus mati
 *   board_build.partitions = huge_app.csv       ; library BLE besar
 *
 * ===================== PERINGATAN KESELAMATAN (BACA) =====================
 *  - Bagian motor (inverter 310 V) BELUM PERNAH diuji di perangkat keras. Uji bertahap sesuai panduan 5.9:
 *    trafo isolasi 1:1 + lampu seri 100-200 W, drum KOSONG, mulai dari "MLEARN" dan "MTEST" putaran rendah.
 *  - Polaritas input IPM diasumsikan AKTIF-HIGH (HIN/LIN = HIGH berarti saklar ON). CEK datasheet IKCM15F60GA
 *    sebelum bus 310 V dihidupkan. Kalau ternyata aktif-LOW, JANGAN pakai firmware ini; kabari untuk diubah.
 *  - Level sakelar air + sensor kunci hanya valid saat kontak "terkunci" tertutup (jalur NET_1 dari CN12).
 *  - Pengaman hardware (sakelar level pin A seri katup isi, MCB, ELCB) tidak boleh dilepas.
 *
 * ===================== PIN (dibaca dari netlist PCB1 / FlyingProbeTesting.json) =====================
 *  RLY1 GPIO12 CN3 katup isi (lewat sakelar level pin A) | RLY2 GPIO14 CN2 pompa buang
 *  RLY3 GPIO27 CN4 aktuator kunci pintu (PTC)            | RLY4 GPIO26 CN5 pompa sabun
 *  Buzzer GPIO19 | Knob CLK 4, DT 5, SW 25 | Start 2 | OLED SDA 23, SCL 18
 *  Sensor kunci pintu (U4) GPIO1, LOW = kontak terkunci | Sakelar level (U5) GPIO3, LOW = air sudah di batas (B tertutup)
 *  IPM: HIN U/V/W = GPIO13/17/21, LIN U/V/W = GPIO15/16/22, VFO (fault, aktif LOW) = GPIO34
 *  Hall A/B/C = GPIO36/39/35 (pull-up eksternal)
 *
 * ===================== ALUR DI MESIN =====================
 *  OFF -> putar knob 1 klik (kanan = 30 MINS, kiri = 60 MINS) -> mesin ON, layar menampilkan pilihan.
 *  Putar terus untuk ganti program. TEKAN knob (atau Start) -> mesin jalan. Selesai -> bunyi -> OFF sendiri.
 *  Saat jalan:  tekan singkat = JEDA / LANJUT
 *               tahan 2 detik = STOP (motor berhenti, air dibuang sampai kosong, kunci dilepas, OFF)
 *               tahan 5 detik = MATI DARURAT (semua relay mati seketika)
 *  JEDA: kunci pintu HANYA dilepas jika drum sudah berhenti dan tidak ada air (level kosong).
 *        Saat ada air (mis. membilas) kunci tetap terkunci walau dijeda. Kunci PTC butuh 1-3 menit untuk benar-benar lepas.
 *  Kontak kunci hilang saat jalan -> otomatis JEDA (bukan berhenti), buzzer warning, lanjut sesuai setting door_resume.
 *  Mode uji hardware: tahan knob saat power-on (relay satu per satu + tampilan input). LEPAS BEBAN dulu.
 *
 * ===================== TAHAPAN PROGRAM =====================
 *  CUCI  : sabun dulu (jika soap_en dan soapS>0) -> isi air sampai level penuh -> bolak-balik (tumble) sampai waktu tahap habis
 *  BILAS : buang air (jika ada) -> isi air -> bolak-balik
 *  PERAS (blok spinMin menit): buang air + putar pelan (sampai menit spinMin-8), menit 8..2 putaran kencang
 *          (cek keseimbangan beban dulu), menit 2..0 melambat dan persiapan selesai.
 *  60 MINS = 2x siklus 30 MINS. RINSE SPIN = bilas + peras (20 menit). SPIN = peras saja (12 menit).
 *  Waktu program berhenti sementara jika tahap isi/buang air belum selesai di ujung tahap.
 *
 * ===================== PROTOKOL BLE (kompatibel Nordic UART, sama dengan dryer) =====================
 * Nama perangkat: nama mesin (default "Washer"). Service 6e400001-b5a3-f393-e0a9-e50e24dcca9e
 * RX (app TULIS) 6e400002-..., TX (NOTIFY) 6e400003-... ; app WAJIB requestMtu(185).
 * PERINTAH (* = tanpa AUTH):
 *   AUTH <pin>  (default 123456)  *GET  *STOP  *EMERG
 *   SEL <1..12>   pilih program (1=30 MINS,2=60 MINS,3=RINSE SPIN,4=SPIN,5=COTTON,6=COTTON+,7=MIXED FABRIC,
 *                 8=ALLERGY CARE,9=ACTIVEWEAR,10=HAND/WOOL,11=DELICATES,12=TUBCLEAN)
 *   START (butuh remote_start=1)   PAUSE   RESUME
 *   SET <kunci> <nilai>     (hanya saat mesin tidak berjalan)
 *   PSET <id> <cycles> <washMin> <rinses> <rinseMin> <spinMin> <onS> <offS> <tumbleRpm> <spinRpm> <soapS>
 *   RING <p1..p12>          urutan program di knob (permutasi 1..12); putar kanan dari OFF = p1, ..., putar kiri dari OFF = p12
 *   NAME <teks>   SAVE   LOAD   DEFAULTS (PIN, nama, hasil MLEARN tetap)
 *   MLEARN                  belajar urutan fasa/Hall otomatis (drum KOSONG, mesin OFF/pilih). Hasil disimpan otomatis.
 *   MTEST <dir 0/1> <rpm 20..250> <detik 3..30>   uji putar motor
 *   SOAP <detik 1..30>      uji pompa sabun (untuk kalibrasi dosis di aplikasi)
 * NOTIFIKASI:
 *   S,<state>,<prog>,<sisaDetik>,<totalDetik>,<tahap>,<rpm>,<kontakKunci>,<relayKunci>,<levelPenuh>,<isi>,<buang>,<sabun>,<motor>,<fault>,<motorSudahDipelajari>,<percobaanSeimbang>,<belumDisimpan>
 *     state: 0 OFF,1 PILIH,2 JALAN,3 JEDA MANUAL,4 JEDA KUNCI,5 STOP-BUANG AIR,6 SELESAI,7 ERROR,8 UJI
 *     tahap: 0 -,1 mengunci,2 sabun,3 isi air,4 tumble,5 buang air,6 buang(peras),7 seimbang,8 redistribusi,9 naik putaran,10 tahan,11 melambat
 *   M,<rpm*10>,<duty permil>,<hallEdges>,<kodeHall>,<riak*10>,<vfoOK>   (diagnosa motor, tiap detik)
 *   C,<kunci>,<nilai>  P,<id>,<nama>,<cycles>,<washMin>,<rinses>,<rinseMin>,<spinMin>,<onS>,<offS>,<tumbleRpm>,<spinRpm>,<soapS>
 *   V,<versi>,WASHER   N,<nama>   R,<p1..p12> (penutup dump GET)
 *   E,DONE | E,DOOR_OPEN | E,LOCK_LOST | E,FAULT,<kode> | E,WARN,UNBAL | E,IPM_TRIP | E,LEARN,OK,<s>,<k>,<skor> | E,LEARN,FAIL
 * KODE ERROR: E1 pintu tidak terkunci, E4 beban tidak seimbang (jika unbal_abort=1), E5 air tidak masuk,
 *             E6 air tidak keluar, E7 motor macet / Hall bermasalah, E8 motor belum dipelajari (jalankan MLEARN), E9 IPM trip berulang
 */
#include <Arduino.h>
#include <Wire.h>
#include <stdarg.h>
#include <strings.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <esp_task_wdt.h>
#include <esp_timer.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#if __has_include(<BLE2902.h>)
#include <BLE2902.h>
#define HAS_BLE2902 1
#endif
#include "soc/gpio_reg.h"
#include "esp_rom_sys.h"

#define FW_VERSION "1.0"
#define MACHINE_TYPE "WASHER"
#define ENC_REVERSE 0
#define ENC_STEPS_PER_DETENT 4
#define OLED_ADDR 0x3C
#define DOOR_DEBOUNCE_MS 150
#define LVL_DEBOUNCE_MS 150
#define CFG_MAGIC 0xC0DE0100UL
#define NPROG 12
#define RING_N 13                 // posisi knob: 0 = OFF, 1..12 = program
#define PWM_FREQ 20000
#define PWM_RES 10                // duty 0..1023

// ===================== PIN =====================
const uint8_t PIN_RELAY_FILL = 12, PIN_RELAY_DRAIN = 14, PIN_RELAY_LOCK = 27, PIN_RELAY_SOAP = 26;
const uint8_t PIN_BUZZER = 19;
const uint8_t PIN_ENC_CLK = 4, PIN_ENC_DT = 5, PIN_ENC_SW = 25, PIN_START = 2;
const uint8_t PIN_DOOR = 1, PIN_LEVEL = 3, PIN_FAULT = 34;
const uint8_t PIN_SDA = 23, PIN_SCL = 18;
const uint8_t HALL_A = 36, HALL_B = 39, HALL_C = 35;       // semua di GPIO.in1 (bit = pin - 32)
static const DRAM_ATTR uint8_t HI_PIN[3] = {13, 17, 21};   // HIN U, V, W
static const DRAM_ATTR uint8_t LO_PIN[3] = {15, 16, 22};   // LIN U, V, W

// ===================== PARAMETER TETAP =====================
const uint32_t SELECT_IDLE_MS = 60000UL, DONE_SHOW_MS = 8000UL, DOOR_RESUME_MS = 2000UL, PAUSE_TIMEOUT_MS = 600000UL;
const uint32_t HOLD_STOP_MS = 2000UL, HOLD_EMERG_MS = 5000UL, HOLD_OFF_SELECT_MS = 1500UL;

// ===================== KONFIGURASI (disimpan di flash/NVS) =====================
struct WProg { uint8_t cycles, washMin, rinses, rinseMin, spinMin, onS, offS, tumbleRpm; uint16_t spinRpm; uint8_t soapS; };
const char* const PNAMES[NPROG] = {"30 MINS", "60 MINS", "RINSE SPIN", "SPIN", "COTTON", "COTTON+", "MIXED FABRIC",
                                   "ALLERGY CARE", "ACTIVEWEAR", "HAND/WOOL", "DELICATES", "TUBCLEAN"};
const WProg DEF_PROGS[NPROG] = {
  //cyc wash rin rMin spin onS offS tRpm spinRpm soap
  {1, 10, 1, 10, 10, 12, 3, 45,  800, 6},    // 30 MINS
  {2, 10, 1, 10, 10, 12, 3, 45,  800, 6},    // 60 MINS = 2x 30 MINS
  {1,  0, 1, 10, 10, 12, 3, 45,  800, 0},    // RINSE SPIN = 20 menit
  {1,  0, 0,  0, 12,  0, 0,  0,  900, 0},    // SPIN = 12 menit
  {1, 30, 2, 12, 12, 12, 3, 50, 1000, 8},    // COTTON      (perkiraan, sesuaikan dari aplikasi)
  {1, 40, 3, 12, 14, 12, 3, 50, 1000, 8},    // COTTON+
  {1, 20, 2, 10, 10, 10, 3, 40,  800, 6},    // MIXED FABRIC
  {1, 40, 3, 15, 12, 12, 3, 45,  900, 8},    // ALLERGY CARE (tanpa pemanas: bilas lebih banyak)
  {1, 15, 1, 10, 10, 10, 3, 40,  800, 6},    // ACTIVEWEAR
  {1, 15, 1, 10, 10,  6, 6, 30,  400, 5},    // HAND/WOOL
  {1, 15, 2,  8, 10,  8, 4, 35,  600, 5},    // DELICATES
  {1, 40, 2, 10, 10, 12, 3, 55, 1000, 0}};   // TUBCLEAN
uint16_t totalMin(const WProg& p) { return (uint16_t)p.cycles * (p.washMin + p.rinses * p.rinseMin + p.spinMin); }

struct Cfg {
  uint32_t magic;
  uint8_t doorAutoResume, remoteStart, soapEn, unbalRetry, unbalAbort, dirInvert, motS, motK, motOk;
  uint16_t fillTimeout, drainTimeout, drainExtra, lockWait, hallPerRev, dutyStart, dutyMax, accel, drainRpm, balanceRpm, finishRpm, learnDuty, stallS;
  uint32_t pin;
  float kp, ki, unbalPct;
  WProg prog[NPROG];
  uint8_t ring[NPROG];
  char name[24];
};
Cfg cfg;
bool cfgDirty = false;

enum PT : uint8_t { PT_U8, PT_U16, PT_U32, PT_F };
struct Param { const char* key; PT t; void* p; float lo, hi; };
const Param PARAMS[] = {
  {"door_resume",  PT_U8,  &cfg.doorAutoResume, 0, 1},
  {"remote_start", PT_U8,  &cfg.remoteStart,    0, 1},
  {"soap_en",      PT_U8,  &cfg.soapEn,         0, 1},
  {"fill_timeout", PT_U16, &cfg.fillTimeout,    30, 600},
  {"drain_timeout",PT_U16, &cfg.drainTimeout,   60, 900},
  {"drain_extra",  PT_U16, &cfg.drainExtra,     5, 120},
  {"lock_wait",    PT_U16, &cfg.lockWait,       10, 90},
  {"hall_per_rev", PT_U16, &cfg.hallPerRev,     6, 2000},
  {"duty_start",   PT_U16, &cfg.dutyStart,      20, 300},
  {"duty_max",     PT_U16, &cfg.dutyMax,        100, 950},
  {"kp",           PT_F,   &cfg.kp,             0.05f, 5},
  {"ki",           PT_F,   &cfg.ki,             0.05f, 10},
  {"accel",        PT_U16, &cfg.accel,          5, 400},
  {"drain_rpm",    PT_U16, &cfg.drainRpm,       0, 200},
  {"balance_rpm",  PT_U16, &cfg.balanceRpm,     50, 300},
  {"finish_rpm",   PT_U16, &cfg.finishRpm,      0, 200},
  {"unbal_pct",    PT_F,   &cfg.unbalPct,       5, 80},
  {"unbal_retry",  PT_U8,  &cfg.unbalRetry,     0, 5},
  {"unbal_abort",  PT_U8,  &cfg.unbalAbort,     0, 1},
  {"learn_duty",   PT_U16, &cfg.learnDuty,      20, 200},
  {"dir_invert",   PT_U8,  &cfg.dirInvert,      0, 1},
  {"stall_s",      PT_U16, &cfg.stallS,         1, 10},
  {"mot_s",        PT_U8,  &cfg.motS,           0, 1},      // hasil MLEARN: 0 = +1, 1 = -1
  {"mot_k",        PT_U8,  &cfg.motK,           0, 5},      // hasil MLEARN
  {"mot_ok",       PT_U8,  &cfg.motOk,          0, 1},      // 1 = sudah dipelajari
  {"pin",          PT_U32, &cfg.pin,            0, 999999}};

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
  cfg.magic = CFG_MAGIC; cfg.doorAutoResume = 1; cfg.remoteStart = 0; cfg.soapEn = 1; cfg.unbalRetry = 3; cfg.unbalAbort = 0;
  cfg.dirInvert = 0; cfg.motS = 0; cfg.motK = 0; cfg.motOk = 0;
  cfg.fillTimeout = 60; cfg.drainTimeout = 240; cfg.drainExtra = 25; cfg.lockWait = 30; cfg.hallPerRev = 144;
  cfg.dutyStart = 60; cfg.dutyMax = 600; cfg.accel = 40; cfg.drainRpm = 40; cfg.balanceRpm = 90; cfg.finishRpm = 60;
  cfg.learnDuty = 70; cfg.stallS = 3; cfg.pin = 123456;
  cfg.kp = 0.8f; cfg.ki = 1.5f; cfg.unbalPct = 30.0f;
  memcpy(cfg.prog, DEF_PROGS, sizeof(DEF_PROGS));
  const uint8_t defRing[NPROG] = {1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 2};   // kanan dari OFF = 30 MINS ... kiri dari OFF = 60 MINS
  memcpy(cfg.ring, defRing, NPROG);
  strncpy(cfg.name, "Washer", 23);
}
bool progSane(const WProg& p) {
  if (p.cycles < 1 || p.cycles > 3 || p.rinses > 4 || p.washMin > 120 || p.rinseMin > 60 || p.soapS > 60) return false;
  if (p.washMin && p.washMin < 3) return false;
  if (p.rinses && p.rinseMin < 5) return false;
  if (p.spinMin && (p.spinMin < 10 || p.spinMin > 40 || p.spinRpm < 100 || p.spinRpm > 1600)) return false;
  if (p.washMin || p.rinses) { if (p.onS < 3 || p.onS > 60 || p.offS < 1 || p.offS > 30 || p.tumbleRpm < 20 || p.tumbleRpm > 120) return false; }
  uint16_t t = totalMin(p);
  return t >= 5 && t <= 480;
}
bool cfgSane() {
  for (const Param& q : PARAMS) { float v = getParamVal(q); if (v < q.lo || v > q.hi) return false; }
  for (int i = 0; i < NPROG; i++) if (!progSane(cfg.prog[i])) return false;
  if (cfg.name[23] != 0 || cfg.name[0] == 0) return false;
  for (int k = 0; cfg.name[k]; k++) if ((uint8_t)cfg.name[k] < 0x20 || (uint8_t)cfg.name[k] > 0x7E) return false;
  uint32_t seen = 0;
  for (int k = 0; k < NPROG; k++) { uint8_t v = cfg.ring[k]; if (v < 1 || v > NPROG) return false; seen |= (1UL << v); }
  if (seen != 0x1FFEUL) return false;                      // ring harus permutasi 1..12
  return true;
}
Preferences prefs;
void cfgLoad() {
  cfgDefaults();
  prefs.begin("washer", true);
  if (prefs.getBytesLength("cfg") == sizeof(Cfg)) {
    Cfg t; prefs.getBytes("cfg", &t, sizeof(Cfg));
    if (t.magic == CFG_MAGIC) { Cfg keep = cfg; cfg = t; if (!cfgSane()) cfg = keep; }
  }
  prefs.end();
  cfgDirty = false;
}
bool cfgSave() {
  prefs.begin("washer", false);
  size_t n = prefs.putBytes("cfg", &cfg, sizeof(Cfg));
  prefs.end();
  return n == sizeof(Cfg);
}

// ===================== BUZZER (sama dengan dryer) =====================
struct Seg { uint16_t on, off; };
const Seg P_TICK[]   = {{12, 0}};
const Seg P_PRESS[]  = {{120, 0}};
const Seg P_START[]  = {{100, 80}, {100, 0}};
const Seg P_POWERON[]= {{60, 60}, {60, 60}, {60, 0}};
const Seg P_DONE[]   = {{400, 200}, {400, 200}, {700, 0}};
const Seg P_STOP[]   = {{600, 0}};
const Seg P_EMERG[]  = {{400, 150}, {400, 0}};
const Seg P_FAULT[]  = {{80, 80}, {80, 80}, {80, 80}, {80, 80}, {80, 80}, {80, 0}};
const Seg P_WARN[]   = {{250, 250}};
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
enum St : uint8_t { S_OFF, S_SELECT, S_RUN, S_PAUSE_MAN, S_PAUSE_LOCK, S_STOPDRAIN, S_DONE, S_FAULT, S_TEST };
enum Sub : uint8_t { SB_NONE, SB_LOCK, SB_SOAP, SB_FILL, SB_TUMBLE, SB_DRAIN, SB_DRAINWAIT, SB_BAL, SB_REDIST, SB_RAMP, SB_HOLD, SB_DECEL };
enum SegT : uint8_t { SG_WASH, SG_RINSE, SG_SDRAIN, SG_SHIGH, SG_SFIN };
struct Stage { uint8_t type; uint32_t endMs; };
Adafruit_SSD1306 oled(128, 64, &Wire, -1);
Stage plan[24]; uint8_t planN = 0, planI = 0;
St st = S_OFF; Sub sub = SB_NONE, lockNext = SB_NONE, pausedSub = SB_NONE;
uint8_t ringIdx = 1, lastRing = 1, faultCode = 0;
uint32_t totalMs = 0, runMs = 0, lastTick = 0, stateT = 0, idleT = 0, subT = 0, fillT0 = 0, drainT0 = 0, emptySince = 0, doorClosedAt = 0;
bool oledOn = false, lockOn = false, fillOn = false, drainOn = false, soapOn = false, sawWater = false;
uint32_t lockOnAt = 0;
bool doorLocked = false; uint32_t lastLowMs = 0;
bool lvlRaw = false; uint32_t lvlT = 0, lastLvlLowMs = 0;

const WProg& prog() { return cfg.prog[(ringIdx ? ringIdx : 1) - 1]; }
const char* progName() { return PNAMES[(ringIdx ? ringIdx : 1) - 1]; }
bool idleState() { return st == S_OFF || st == S_SELECT || st == S_DONE || st == S_FAULT; }
uint8_t posOfProg(uint8_t p) { if (!p) return 0; for (uint8_t k = 0; k < NPROG; k++) if (cfg.ring[k] == p) return k + 1; return 0; }
uint8_t progAtPos(uint8_t pos) { return pos ? cfg.ring[pos - 1] : 0; }

// ===================== ANTRIAN BLE (TX) =====================
#define TXQ_N 64
#define TX_LEN 96
BLECharacteristic* txChar = nullptr;
volatile bool bleConn = false, authed = false;
char txq[TXQ_N][TX_LEN]; uint8_t txHead = 0, txTail = 0; uint32_t txLast = 0;
void txPush(const char* fmt, ...) {
  if (!bleConn) return;
  uint8_t nx = (txHead + 1) % TXQ_N; if (nx == txTail) return;
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

void doFault(uint8_t code);
void beginSub(Sub s, uint32_t now);
void goOff();

// ===================== OUTPUT RELAY =====================
void setLock(bool on) { if (on && !lockOn) lockOnAt = millis(); lockOn = on; digitalWrite(PIN_RELAY_LOCK, on); }
bool lockReady() { return lockOn && doorLocked && (millis() - lockOnAt) > 1500UL; }
void setFill(bool on) { if (on && !lockReady()) on = false; fillOn = on; digitalWrite(PIN_RELAY_FILL, on); }
void setDrain(bool on) { drainOn = on; digitalWrite(PIN_RELAY_DRAIN, on); }
void setSoap(bool on) { if (on && !lockReady()) on = false; soapOn = on; digitalWrite(PIN_RELAY_SOAP, on); }

// ===================== SENSOR PINTU (kontak terkunci) DAN LEVEL AIR =====================
void doorSample(uint32_t now) {
  if (digitalRead(PIN_DOOR) == LOW) lastLowMs = now;
  doorClosed_dummy: ;
  doorLocked = (now - lastLowMs) < DOOR_DEBOUNCE_MS;
}
void levelSample(uint32_t now) {
  if (digitalRead(PIN_LEVEL) == LOW) lastLvlLowMs = now;
  bool raw = doorLocked && (now - lastLvlLowMs) < LVL_DEBOUNCE_MS;     // valid hanya jika kontak kunci tertutup
  if (raw != lvlRaw) { lvlRaw = raw; lvlT = now; }
}
bool levelFullStable(uint32_t now, uint32_t ms) { return lvlRaw && now - lvlT >= ms; }
bool levelEmptyStable(uint32_t now, uint32_t ms) { return !lvlRaw && now - lvlT >= ms; }

// ===================== DRIVER MOTOR BLDC (6-step + Hall) =====================
// Fase: 0=U, 1=V, 2=W. Langkah: U+V-, U+W-, V+W-, V+U-, W+U-, W+V-.
static const DRAM_ATTR uint8_t STEP_HI[6] = {0, 0, 1, 1, 2, 2};
static const DRAM_ATTR uint8_t STEP_LO[6] = {1, 2, 2, 0, 0, 1};
static const DRAM_ATTR int8_t POS_OF[8] = {-1, 0, 2, 1, 4, 5, 3, -1};   // urutan siklik kode Hall: 1,3,2,6,4,5
volatile uint8_t tbl[2][8];
volatile int8_t curHi = -1, curLo = -1;
volatile uint16_t pwmDuty = 0;
volatile bool drvEnabled = false;
volatile uint8_t drvDir = 0, hallLast = 0;
volatile uint32_t hallEdges = 0, hallLastUs = 0;
volatile int32_t hallPosAcc = 0;
portMUX_TYPE drvMux = portMUX_INITIALIZER_UNLOCKED;

#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
#define PWM_ATTACH(i) ledcAttach(HI_PIN[i], PWM_FREQ, PWM_RES)
#define PWM_WRITE(i, d) ledcWrite(HI_PIN[i], (d))
#else
#define PWM_ATTACH(i) do { ledcSetup(i, PWM_FREQ, PWM_RES); ledcAttachPin(HI_PIN[i], i); } while (0)
#define PWM_WRITE(i, d) ledcWrite(i, (d))
#endif

static inline uint8_t IRAM_ATTR readHall() {
  uint32_t v = REG_READ(GPIO_IN1_REG);
  return ((v >> (HALL_A - 32)) & 1) | (((v >> (HALL_B - 32)) & 1) << 1) | (((v >> (HALL_C - 32)) & 1) << 2);
}
void IRAM_ATTR drvSet(int8_t hi, int8_t lo) {
  bool conflict = (hi >= 0 && hi == curLo) || (lo >= 0 && lo == curHi);   // satu kaki berpindah high<->low
  for (int i = 0; i < 3; i++) {
    if (i != hi) PWM_WRITE(i, 0);
    if (i != lo) REG_WRITE(GPIO_OUT_W1TC_REG, 1UL << LO_PIN[i]);
  }
  if (conflict) esp_rom_delay_us(70);                    // beri waktu LEDC mengunci duty 0 satu periode penuh
  if (lo >= 0) REG_WRITE(GPIO_OUT_W1TS_REG, 1UL << LO_PIN[lo]);
  if (hi >= 0) PWM_WRITE(hi, pwmDuty);
  curHi = hi; curLo = lo;
}
void IRAM_ATTR drvCommutate(uint8_t h) {
  uint8_t s = tbl[drvDir][h];
  if (s == 255) { drvSet(-1, -1); return; }
  int8_t hi = STEP_HI[s], lo = STEP_LO[s];
  if (hi != curHi || lo != curLo) drvSet(hi, lo);
}
void IRAM_ATTR hallISR() {
  uint8_t h = readHall();
  hallEdges++;
  hallLastUs = (uint32_t)esp_timer_get_time();
  int8_t p0 = POS_OF[hallLast], p1 = POS_OF[h];
  if (p0 >= 0 && p1 >= 0) { int8_t d = (p1 - p0 + 6) % 6; if (d == 1) hallPosAcc++; else if (d == 5) hallPosAcc--; }
  hallLast = h;
  if (drvEnabled) drvCommutate(h);
}
void buildTables(int8_t s, uint8_t k) {     // s = +1/-1 (arah urutan), k = offset langkah. Arah 1 = arah 0 digeser 3 langkah.
  static const uint8_t ord[6] = {1, 3, 2, 6, 4, 5};
  for (int d = 0; d < 2; d++) for (int h = 0; h < 8; h++) tbl[d][h] = 255;
  for (int p = 0; p < 6; p++) for (int d = 0; d < 2; d++) tbl[d][ord[p]] = (uint8_t)((((s * p + k + (d ? 3 : 0)) % 6) + 6) % 6);
}
void drvStart(uint8_t dir, uint16_t duty) {
  portENTER_CRITICAL(&drvMux);
  drvDir = dir; pwmDuty = duty; drvEnabled = true;
  hallLast = readHall();
  drvCommutate(hallLast);
  portEXIT_CRITICAL(&drvMux);
}
void drvStop() {
  portENTER_CRITICAL(&drvMux);
  drvEnabled = false; drvSet(-1, -1);
  portEXIT_CRITICAL(&drvMux);
}
void drvSetDuty(uint16_t duty) {
  portENTER_CRITICAL(&drvMux);
  pwmDuty = duty;
  if (drvEnabled && curHi >= 0) PWM_WRITE(curHi, duty);
  portEXIT_CRITICAL(&drvMux);
}
void drvPrecharge() {                       // isi kapasitor bootstrap: semua saklar bawah ON sebentar (motor tidak boleh berputar)
  for (int i = 0; i < 3; i++) REG_WRITE(GPIO_OUT_W1TS_REG, 1UL << LO_PIN[i]);
  delay(20);
  for (int i = 0; i < 3; i++) REG_WRITE(GPIO_OUT_W1TC_REG, 1UL << LO_PIN[i]);
}
void drvInit() {
  for (int i = 0; i < 3; i++) { pinMode(LO_PIN[i], OUTPUT); digitalWrite(LO_PIN[i], LOW); PWM_ATTACH(i); PWM_WRITE(i, 0); }
  buildTables(cfg.motS ? -1 : 1, cfg.motK);
  hallLast = readHall();
  attachInterrupt(HALL_A, hallISR, CHANGE); attachInterrupt(HALL_B, hallISR, CHANGE); attachInterrupt(HALL_C, hallISR, CHANGE);
}

// ===================== KONTROL KECEPATAN MOTOR =====================
float rpmMeas = 0, rpmRaw = 0, rpmCmd = 0, rpmTarget = 0, integ = 0, dutyNow = 0;
bool motorRun = false; uint8_t motorDirNow = 0;
uint32_t edgesPrev = 0, lastEdgeT = 0, tripT = 0; uint8_t tripCnt = 0;
float rbuf[40]; uint8_t rI = 0, rN = 0;
void ripplePush(float v) { rbuf[rI] = v; rI = (rI + 1) % 40; if (rN < 40) rN++; }
void rippleClear() { rN = 0; rI = 0; }
float ripplePct() {                          // riak kecepatan (maks-min)/rata2 dalam ~2 detik terakhir, persen
  if (rN < 30) return 0;
  float mn = 1e9f, mx = -1e9f, sum = 0;
  for (int i = 0; i < rN; i++) { float v = rbuf[i]; if (v < mn) mn = v; if (v > mx) mx = v; sum += v; }
  float avg = sum / rN;
  return avg > 20.0f ? (mx - mn) / avg * 100.0f : 0.0f;
}
uint16_t toPwm(float permil) { return (uint16_t)(permil * 1023.0f / 1000.0f); }
bool motorStopped() { return !motorRun && ((uint32_t)esp_timer_get_time() - hallLastUs) > 2000000UL; }
void motorStop() { motorRun = false; rpmTarget = 0; rpmCmd = 0; integ = 0; dutyNow = 0; drvStop(); }
bool motorStart(uint8_t dir, float rpm) {
  if (!cfg.motOk) { doFault(8); return false; }
  if (!(lockOn && doorLocked)) return false;                 // bus 310 V hanya ada saat kontak kunci tertutup
  if (digitalRead(PIN_FAULT) == LOW) return false;
  rpmTarget = rpm;
  if (!motorRun) {
    drvPrecharge();
    motorRun = true; motorDirNow = dir; rpmCmd = 0; integ = cfg.dutyStart; dutyNow = integ;
    edgesPrev = hallEdges; lastEdgeT = millis();
    drvStart(dir ^ cfg.dirInvert, toPwm(dutyNow));
  }
  return true;
}
void motorSetTarget(float rpm) { rpmTarget = rpm; }
void motorTick(uint32_t now) {
  static uint32_t t0 = 0;
  if (now - t0 < 50) return;
  float dt = (now - t0) / 1000.0f; t0 = now;
  uint32_t e = hallEdges; uint32_t de = e - edgesPrev; edgesPrev = e;
  rpmRaw = (de / dt) * 60.0f / (float)cfg.hallPerRev;
  rpmMeas = rpmMeas * 0.6f + rpmRaw * 0.4f;
  ripplePush(rpmRaw);
  if (!motorRun) return;
  float step = (float)cfg.accel * dt;
  if (rpmCmd < rpmTarget) { rpmCmd += step; if (rpmCmd > rpmTarget) rpmCmd = rpmTarget; }
  else { rpmCmd -= step; if (rpmCmd < rpmTarget) rpmCmd = rpmTarget; }
  if (rpmTarget < 1.0f && rpmMeas < 4.0f) { motorStop(); return; }
  float err = rpmCmd - rpmMeas;
  integ += cfg.ki * err * dt;
  if (integ < 0) integ = 0;
  if (integ > cfg.dutyMax) integ = cfg.dutyMax;
  float d = integ + cfg.kp * err;
  if (d < 0) d = 0;
  if (d > cfg.dutyMax) d = cfg.dutyMax;
  dutyNow = d; drvSetDuty(toPwm(d));
  if (de > 0) lastEdgeT = now;
  else if (now - lastEdgeT > (uint32_t)cfg.stallS * 1000UL) { motorStop(); doFault(7); }
}
void ipmFaultCheck(uint32_t now) {
  static bool prev = false;
  bool f = digitalRead(PIN_FAULT) == LOW;
  if (f && !prev && (drvEnabled || motorRun)) {
    motorStop();
    if (now - tripT > 30000UL) tripCnt = 0;
    tripT = now;
    if (++tripCnt >= 3) doFault(9); else txPush("E,IPM_TRIP");
  }
  prev = f;
}

// ===================== DISPLAY =====================
void oledPower(bool on) { if (on == oledOn) return; oledOn = on; oled.ssd1306_command(on ? SSD1306_DISPLAYON : SSD1306_DISPLAYOFF); }
void txt(int x, int y, uint8_t size, const char* s, bool center = false) {
  oled.setTextSize(size); int w = strlen(s) * 6 * size; if (center) x = (128 - w) / 2;
  oled.setCursor(x < 0 ? 0 : x, y); oled.print(s);
}
void txtFit(int y, const char* s) { txt(0, y, (strlen(s) * 12 <= 128) ? 2 : 1, s, true); }
void fmtTime(char* b, uint32_t sec, bool& big) {
  if (sec >= 3600) { sprintf(b, "%lu:%02lu:%02lu", (unsigned long)(sec / 3600), (unsigned long)((sec / 60) % 60), (unsigned long)(sec % 60)); big = false; }
  else { sprintf(b, "%02lu:%02lu", (unsigned long)(sec / 60), (unsigned long)(sec % 60)); big = true; }
}
void drawHold(uint32_t held) {
  if (held < 300) return;
  int w = held >= HOLD_STOP_MS ? (int)(128UL * (held - HOLD_STOP_MS) / (HOLD_EMERG_MS - HOLD_STOP_MS)) : (int)(128UL * held / HOLD_STOP_MS);
  oled.fillRect(0, 56, 128, 8, SSD1306_BLACK); oled.drawRect(0, 56, 128, 8, SSD1306_WHITE); oled.fillRect(0, 56, w > 128 ? 128 : w, 8, SSD1306_WHITE);
}
const char* subText() {
  switch (sub) {
    case SB_LOCK: return "MENGUNCI PINTU";
    case SB_SOAP: return "SABUN";
    case SB_FILL: return "ISI AIR";
    case SB_TUMBLE: return plan[planI].type == SG_WASH ? "MENCUCI" : "MEMBILAS";
    case SB_DRAIN: case SB_DRAINWAIT: return "BUANG AIR";
    case SB_BAL: case SB_REDIST: return "MERATAKAN BEBAN";
    case SB_RAMP: case SB_HOLD: return "MENGERINGKAN";
    case SB_DECEL: return "FINISH...";
    default: return "";
  }
}
const char* faultLine(uint8_t c) {
  switch (c) {
    case 1: return "PINTU TDK TERKUNCI";
    case 4: return "BEBAN TDK SEIMBANG";
    case 5: return "AIR TIDAK MASUK";
    case 6: return "AIR TIDAK KELUAR";
    case 7: return "MOTOR MACET / HALL";
    case 8: return "MOTOR BLM DIPELAJARI";
    case 9: return "DRIVER MOTOR TRIP";
    default: return "ERROR";
  }
}
void drawUI(uint32_t now, uint32_t held) {
  char b[26]; bool big;
  oled.clearDisplay(); oled.setTextColor(SSD1306_WHITE);
  static bool lastInv = false;
  bool inv = (st == S_PAUSE_LOCK && !doorLocked && ((now / 400) & 1));
  if (inv != lastInv) { oled.invertDisplay(inv); lastInv = inv; }
  switch (st) {
    case S_OFF: break;
    case S_SELECT:
      txt(0, 0, 1, "PILIH PROGRAM", true);
      if (bleConn) oled.fillCircle(124, 3, 2, SSD1306_WHITE);
      if (ringIdx == 0) { txt(0, 22, 3, "OFF", true); txt(0, 56, 1, "TEKAN = MATI", true); }
      else {
        txtFit(16, progName());
        uint16_t m = totalMin(prog());
        if (m >= 60) sprintf(b, "%u JAM %02u MENIT", m / 60, m % 60); else sprintf(b, "%u MENIT", m);
        txt(0, 38, 1, b, true); txt(0, 56, 1, "TEKAN = MULAI", true);
      }
      break;
    case S_RUN: case S_PAUSE_MAN: case S_PAUSE_LOCK: {
      txt(0, 0, 1, progName());
      if (bleConn) oled.fillCircle(78, 3, 2, SSD1306_WHITE);
      if (motorRun) { sprintf(b, "%drpm", (int)(rpmMeas + 0.5f)); txt(128 - strlen(b) * 6, 0, 1, b); }
      uint32_t rem = totalMs > runMs ? (totalMs - runMs + 999) / 1000 : 0; fmtTime(b, rem, big);
      txt(0, 16, big ? 3 : 2, b, true);
      if (st == S_PAUSE_LOCK) {
        if (!doorLocked) txt(0, 46, 1, "KUNCI TERLEPAS!", true);
        else if (cfg.doorAutoResume) txt(0, 46, 1, "MELANJUTKAN...", true);
        else txt(0, 46, 1, "KUNCI OK - TEKAN LANJUT", true);
      } else if (st == S_PAUSE_MAN) {
        txt(0, 42, 1, "JEDA - TEKAN LANJUT", true);
        txt(0, 50, 1, lockOn ? "PINTU TERKUNCI" : "KUNCI DILEPAS", true);
      } else txt(0, 46, 1, subText(), true);
      if (held > 0) drawHold(held); else { oled.drawRect(0, 58, 128, 5, SSD1306_WHITE); oled.fillRect(0, 58, (int)(128UL * runMs / (totalMs ? totalMs : 1)), 5, SSD1306_WHITE); }
      break; }
    case S_STOPDRAIN: txt(0, 6, 2, "STOP", true); txt(0, 30, 1, "BUANG AIR...", true); txt(0, 50, 1, lvlRaw ? "AIR MASIH ADA" : "AIR HABIS", true); break;
    case S_DONE: txt(0, 14, 2, "SELESAI", true); txt(0, 40, 1, lockOn ? "TUNGGU PINTU TERBUKA" : "MESIN OFF...", true); break;
    case S_FAULT: sprintf(b, "ERROR E%u", faultCode); txt(0, 8, 2, b, true);
      txt(0, 34, 1, faultLine(faultCode), true); txt(0, 52, 1, "TEKAN = OFF", true); break;
    case S_TEST: txt(0, 10, 2, "UJI", true); txt(0, 36, 1, "JANGAN BUKA PINTU", true); break;
  }
  oled.display();
}

// ===================== RENCANA TAHAPAN PROGRAM =====================
uint8_t unbalTries = 0; bool unbalWarned = false; uint16_t spinLimit = 0; uint32_t monT = 0;
uint8_t tmPhase = 1, tmDir = 0; uint32_t tmT = 0;

void buildPlan() {
  const WProg& p = prog(); planN = 0; uint32_t t = 0;
  auto add = [&](uint8_t type, uint32_t minutes) {
    if (minutes == 0 || planN >= 24) return;
    t += minutes * 60000UL; plan[planN].type = type; plan[planN].endMs = t; planN++;
  };
  for (uint8_t c = 0; c < p.cycles; c++) {
    if (p.washMin) add(SG_WASH, p.washMin);
    for (uint8_t r = 0; r < p.rinses; r++) add(SG_RINSE, p.rinseMin);
    if (p.spinMin) { add(SG_SDRAIN, p.spinMin - 8); add(SG_SHIGH, 6); add(SG_SFIN, 2); }
  }
  totalMs = t; planI = 0;
}
bool stageIncomplete() {
  switch (plan[planI].type) {
    case SG_WASH: return sub == SB_SOAP || sub == SB_FILL || sub == SB_LOCK;
    case SG_RINSE: return sub == SB_DRAIN || sub == SB_FILL || sub == SB_LOCK;
    case SG_SDRAIN: return sub == SB_DRAIN || sub == SB_LOCK;
    default: return false;
  }
}
void tumbleReset(uint32_t now) { tmPhase = 1; tmT = now - 100000UL; }
void tumbleTick(uint32_t now, uint8_t rpm, uint8_t onS, uint8_t offS) {
  if (rpm == 0) return;
  if (tmPhase == 0) {
    if (!motorRun) motorStart(tmDir, rpm); else motorSetTarget(rpm);
    if (now - tmT >= (uint32_t)onS * 1000UL) { motorStop(); tmPhase = 1; tmT = now; }
  } else if (now - tmT >= (uint32_t)offS * 1000UL && motorStopped()) {
    tmDir ^= 1; tmPhase = 0; tmT = now; motorStart(tmDir, rpm);
  }
}
void beginSub(Sub s, uint32_t now) {
  sub = s; subT = now;
  switch (s) {
    case SB_LOCK: setLock(true); break;
    case SB_SOAP: setSoap(true); break;
    case SB_FILL: setSoap(false); setDrain(false); setFill(true); fillT0 = now; break;
    case SB_TUMBLE: tumbleReset(now); break;
    case SB_DRAIN: setFill(false); setDrain(true); drainT0 = now; emptySince = 0; if (plan[planI].type == SG_SDRAIN) tumbleReset(now); break;
    case SB_DRAINWAIT: tumbleReset(now); break;
    case SB_BAL: setDrain(true); rippleClear(); break;
    case SB_REDIST: tumbleReset(now); break;
    case SB_RAMP: case SB_HOLD: monT = now; break;
    default: break;
  }
}
void beginStage(uint32_t now) {
  const WProg& p = prog();
  uint8_t t = plan[planI].type;
  if (t != SG_SFIN) motorStop();
  setFill(false); setSoap(false);
  switch (t) {
    case SG_WASH: setDrain(false); beginSub((cfg.soapEn && p.soapS) ? SB_SOAP : SB_FILL, now); break;
    case SG_RINSE: if (lvlRaw) beginSub(SB_DRAIN, now); else { setDrain(false); beginSub(SB_FILL, now); } break;
    case SG_SDRAIN: setDrain(true); beginSub(lvlRaw ? SB_DRAIN : SB_DRAINWAIT, now); break;
    case SG_SHIGH: spinLimit = p.spinRpm; unbalTries = 0; unbalWarned = false; setDrain(true); beginSub(SB_BAL, now); break;
    case SG_SFIN: setDrain(true); beginSub(SB_DECEL, now); break;
  }
}
Sub restartSub(Sub s) {                          // sub-tahap yang diulang setelah JEDA
  switch (s) {
    case SB_SOAP: return SB_FILL;
    case SB_BAL: case SB_REDIST: case SB_RAMP: case SB_HOLD: return SB_BAL;
    case SB_LOCK: return lockNext;
    default: return s;
  }
}
void unbalFail(uint32_t now) {
  if (++unbalTries > cfg.unbalRetry) {
    if (!unbalWarned) { unbalWarned = true; txPush("E,WARN,UNBAL"); }
    if (cfg.unbalAbort) { doFault(4); return; }
    if (spinLimit > 300) spinLimit = 300;        // lanjut peras dengan putaran rendah
    beginSub(SB_RAMP, now);
  } else beginSub(SB_REDIST, now);
}
void spinTick(uint32_t now) {
  switch (sub) {
    case SB_BAL:
      if (!motorRun) { if (!motorStopped()) break; motorStart(0, cfg.balanceRpm); rippleClear(); subT = now; }
      if (now - subT > 60000UL) { unbalFail(now); break; }                      // tidak bisa mencapai putaran seimbang (beban terlalu berat)
      if (now - subT > 9000UL && rpmMeas > cfg.balanceRpm * 0.8f) {
        if (ripplePct() <= cfg.unbalPct) beginSub(SB_RAMP, now); else unbalFail(now);
      }
      break;
    case SB_REDIST:
      tumbleTick(now, 50, 5, 2);
      if (now - subT > 16000UL) { motorStop(); beginSub(SB_BAL, now); }
      break;
    case SB_RAMP: case SB_HOLD: {
      float tgt = spinLimit;
      if (motorRun) motorSetTarget(tgt);
      if (sub == SB_RAMP && rpmMeas >= tgt * 0.97f) beginSub(SB_HOLD, now);
      else if (sub == SB_RAMP && now - subT > 150000UL) beginSub(SB_HOLD, now);   // tidak sanggup mencapai target: tahan di kecepatan yang ada
      if (now - monT >= 2000UL && rpmMeas > 200.0f && !(unbalWarned && spinLimit <= 300)) {
        monT = now;
        if (ripplePct() > cfg.unbalPct * 1.5f) unbalFail(now);
      }
      break; }
    case SB_DECEL:
      if (motorRun) motorSetTarget(cfg.finishRpm);
      else if (cfg.finishRpm > 0 && motorStopped()) motorStart(0, cfg.finishRpm);
      break;
    default: break;
  }
}
void washTick(uint32_t now) {
  const WProg& p = prog();
  switch (sub) {
    case SB_LOCK:
      if (lockReady()) { if (lockNext == SB_NONE) beginStage(now); else beginSub(lockNext, now); }
      else if (now - subT > (uint32_t)cfg.lockWait * 1000UL) doFault(1);
      break;
    case SB_SOAP:
      if (now - subT >= (uint32_t)p.soapS * 1000UL) { setSoap(false); beginSub(SB_FILL, now); }
      break;
    case SB_FILL:
      if (levelFullStable(now, 2500)) { setFill(false); beginSub(SB_TUMBLE, now); }
      else if (now - fillT0 > (uint32_t)cfg.fillTimeout * 1000UL) doFault(5);       // air tidak masuk (belum penuh dalam batas waktu)
      break;
    case SB_TUMBLE: tumbleTick(now, p.tumbleRpm, p.onS, p.offS); break;
    case SB_DRAIN:
      if (plan[planI].type == SG_SDRAIN) tumbleTick(now, (uint8_t)cfg.drainRpm, 8, 3);
      if (levelEmptyStable(now, 1500)) {
        if (!emptySince) emptySince = now;
        if (now - emptySince >= (uint32_t)cfg.drainExtra * 1000UL) {
          if (plan[planI].type == SG_RINSE) { setDrain(false); beginSub(SB_FILL, now); }
          else beginSub(SB_DRAINWAIT, now);                                          // tahap peras: pompa tetap hidup
        }
      } else emptySince = 0;
      if (sub == SB_DRAIN && now - drainT0 > (uint32_t)cfg.drainTimeout * 1000UL) doFault(6);
      break;
    case SB_DRAINWAIT: tumbleTick(now, (uint8_t)cfg.drainRpm, 8, 3); break;
    default: spinTick(now); break;
  }
}

// ===================== TRANSISI =====================
void allOff() { motorStop(); setFill(false); setDrain(false); setSoap(false); setLock(false); sub = SB_NONE; }
void goOff() { allOff(); beepStop(); st = S_OFF; oledPower(false); }
void emergencyOff() { allOff(); beepStop(); BEEP(P_EMERG); st = S_OFF; oledPower(false); }
void powerOn(uint32_t now) { st = S_SELECT; idleT = now; oledPower(true); }
void doFault(uint8_t code) {
  motorStop(); setFill(false); setSoap(false); setDrain(false);
  faultCode = code; st = S_FAULT; stateT = millis(); BEEP(P_FAULT); txPush("E,FAULT,%u", code);
}
bool startRun(uint32_t now) {
  if (!cfg.motOk) { doFault(8); return false; }
  buildPlan();
  if (planN == 0) { BEEP(P_NO); return false; }
  runMs = 0; lastTick = now; lastRing = ringIdx; lockNext = SB_NONE; st = S_RUN;
  beginSub(SB_LOCK, now); BEEP(P_START);
  return true;
}
void pauseRun(St why, uint32_t now) {
  pausedSub = sub;
  setFill(false); setSoap(false); setDrain(false); motorStop();
  st = why; stateT = now;
  if (why == S_PAUSE_LOCK) { beepPattern(P_WARN, 1, true); txPush("E,LOCK_LOST"); } else BEEP(P_PRESS);
}
void resumeRun(uint32_t now) {
  lockNext = restartSub(pausedSub);
  st = S_RUN; lastTick = now; beepStop(); BEEP(P_PRESS);
  beginSub(SB_LOCK, now);                     // kunci ulang pintu (jika sempat dilepas), lalu lanjut
}
void stopAndDrain(uint32_t now) {
  setFill(false); setSoap(false); motorStop();
  st = S_STOPDRAIN; stateT = now; drainT0 = now; emptySince = 0; sawWater = lvlRaw; BEEP(P_STOP);
}
void finishRun(uint32_t now) {
  motorStop(); setFill(false); setSoap(false); setDrain(false);
  st = S_DONE; stateT = now; beepStop(); BEEP(P_DONE); txPush("E,DONE");
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
    case S_PAUSE_MAN: case S_PAUSE_LOCK: if (doorLocked || !lockOn) resumeRun(now); else BEEP(P_NO); break;
    case S_FAULT: BEEP(P_PRESS); if (lockOn) stopAndDrain(now); else goOff(); break;
    case S_STOPDRAIN: BEEP(P_NO); break;
    default: break;
  }
}
bool btnDown = false, stopFired = false, emergFired = false; uint32_t btnAt = 0, btnLast = 0;
void buttonTick(uint32_t now) {
  bool p = (digitalRead(PIN_ENC_SW) == LOW) || (digitalRead(PIN_START) == LOW);
  if (p && !btnDown && now - btnLast > 30) { btnDown = true; btnAt = now; stopFired = emergFired = false; }
  else if (btnDown) {
    uint32_t held = now - btnAt;
    bool running = (st == S_RUN || st == S_PAUSE_MAN || st == S_PAUSE_LOCK);
    if (running && !stopFired && held >= HOLD_STOP_MS) { stopFired = true; stopAndDrain(now); }
    if (st != S_OFF && (st == S_STOPDRAIN || running || stopFired) && !emergFired && held >= HOLD_EMERG_MS) { emergFired = true; emergencyOff(); }
    if (st == S_SELECT && !stopFired && held >= HOLD_OFF_SELECT_MS) { stopFired = true; BEEP(P_PRESS); goOff(); }
    if (!p) {
      btnDown = false; btnLast = now;
      if (!stopFired && !emergFired && held >= 30) onShortPress(now);
    }
  }
}

// ===================== UJI: MLEARN / MTEST / SOAP =====================
uint8_t testKind = 0, testStep = 0, testDir = 0; uint32_t testT = 0, testEnd = 0; float testRpm = 0;
uint8_t lrnI = 0; int32_t lrnScore[12];
void testStart(uint8_t kind, uint32_t now) {
  testKind = kind; testStep = 0; testT = now; st = S_TEST; oledPower(true); BEEP(P_START);
  if (kind == 3) { setSoap(true); }
}
void testFinishOk() { BEEP(P_DONE); st = S_OFF; oledPower(false); setLock(false); }
void testTick(uint32_t now) {
  if (testKind == 3) {                                   // uji pompa sabun
    if (soapOn == false) { digitalWrite(PIN_RELAY_SOAP, HIGH); soapOn = true; }   // pompa sabun tidak butuh kunci untuk uji
    if (now >= testEnd) { digitalWrite(PIN_RELAY_SOAP, LOW); soapOn = false; testFinishOk(); }
    return;
  }
  switch (testStep) {
    case 0: setLock(true); testStep = 1; testT = now; break;
    case 1:
      if (lockReady()) { testStep = 2; testT = now; lrnI = 0; }
      else if (now - testT > (uint32_t)cfg.lockWait * 1000UL) doFault(1);
      break;
    case 2:
      if (testKind == 2) {                               // MTEST
        if (!motorStart(testDir, testRpm)) { if (!cfg.motOk) return; doFault(7); return; }
        testEnd = now + testEnd; testStep = 10; break;   // testEnd berisi durasi (ms) saat dipanggil
      }
      // MLEARN: coba kombinasi (s,k) ke-lrnI
      { int8_t s = (lrnI < 6) ? 1 : -1; uint8_t k = lrnI % 6;
        buildTables(s, k); hallPosAcc = 0; drvPrecharge();
        drvStart(0, toPwm(cfg.learnDuty)); testT = now; testStep = 3; }
      break;
    case 3:
      if (digitalRead(PIN_FAULT) == LOW) { drvStop(); doFault(9); break; }
      if (now - testT >= 700) { lrnScore[lrnI] = hallPosAcc; drvStop(); testT = now; testStep = 4; }
      break;
    case 4:
      if (now - testT >= 600) { if (++lrnI >= 12) testStep = 5; else testStep = 2; }
      break;
    case 5: {
      int best = 0; for (int i = 1; i < 12; i++) if (lrnScore[i] > lrnScore[best]) best = i;
      int8_t s = (best < 6) ? 1 : -1; uint8_t k = best % 6;
      if (lrnScore[best] >= 12) {
        cfg.motS = (s < 0) ? 1 : 0; cfg.motK = k; cfg.motOk = 1; buildTables(s, k);
        if (cfgSave()) cfgDirty = false;
        txPush("E,LEARN,OK,%d,%u,%ld", (int)s, (unsigned)k, (long)lrnScore[best]);
        testStep = 20;
      } else { txPush("E,LEARN,FAIL"); doFault(7); }
      break; }
    case 10:                                              // MTEST berjalan
      if (now >= testEnd) { motorStop(); testStep = 20; }
      break;
    case 20:
      if (motorStopped()) testFinishOk();
      break;
  }
}

// ===================== APLIKASI ANDROID (BLE) =====================
#define SVC_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define RX_UUID  "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define TX_UUID  "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define RXQ_N 6
#define RX_LEN 96
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

uint8_t subCode() {
  if (st != S_RUN && st != S_PAUSE_MAN && st != S_PAUSE_LOCK) return 0;
  switch (sub) {
    case SB_LOCK: return 1; case SB_SOAP: return 2; case SB_FILL: return 3; case SB_TUMBLE: return 4;
    case SB_DRAIN: return 5; case SB_DRAINWAIT: return 6; case SB_BAL: return 7; case SB_REDIST: return 8;
    case SB_RAMP: return 9; case SB_HOLD: return 10; case SB_DECEL: return 11; default: return 0;
  }
}
void sendStatus() {
  bool act = (st == S_RUN || st == S_PAUSE_MAN || st == S_PAUSE_LOCK);
  uint32_t rem = (act && totalMs > runMs) ? (totalMs - runMs + 999) / 1000 : 0;
  txPush("S,%u,%u,%lu,%lu,%u,%d,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u",
         (unsigned)st, (unsigned)ringIdx, (unsigned long)rem, (unsigned long)(totalMs / 1000), (unsigned)subCode(),
         (int)(rpmMeas + 0.5f), (unsigned)doorLocked, (unsigned)lockOn, (unsigned)lvlRaw, (unsigned)fillOn, (unsigned)drainOn,
         (unsigned)soapOn, (unsigned)motorRun, (unsigned)faultCode, (unsigned)cfg.motOk, (unsigned)unbalTries, (unsigned)cfgDirty);
}
void sendMotor() {
  txPush("M,%d,%d,%lu,%u,%d,%u", (int)(rpmMeas * 10.0f), (int)dutyNow, (unsigned long)hallEdges, (unsigned)readHall(),
         (int)(ripplePct() * 10.0f), (unsigned)(digitalRead(PIN_FAULT) == HIGH));
}
void sendCfg() {
  txPush("V,%s,%s", FW_VERSION, MACHINE_TYPE);
  for (const Param& q : PARAMS) {
    if (!strcmp(q.key, "pin")) continue;
    if (q.t == PT_F) txPush("C,%s,%.2f", q.key, getParamVal(q)); else txPush("C,%s,%ld", q.key, (long)getParamVal(q));
  }
  for (int i = 0; i < NPROG; i++) {
    const WProg& p = cfg.prog[i];
    txPush("P,%d,%s,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u", i + 1, PNAMES[i], (unsigned)p.cycles, (unsigned)p.washMin, (unsigned)p.rinses,
           (unsigned)p.rinseMin, (unsigned)p.spinMin, (unsigned)p.onS, (unsigned)p.offS, (unsigned)p.tumbleRpm, (unsigned)p.spinRpm, (unsigned)p.soapS);
  }
  txPush("N,%s", cfg.name);
  txPush("R,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u", cfg.ring[0], cfg.ring[1], cfg.ring[2], cfg.ring[3], cfg.ring[4], cfg.ring[5],
         cfg.ring[6], cfg.ring[7], cfg.ring[8], cfg.ring[9], cfg.ring[10], cfg.ring[11]);   // R = akhir dump setting
  sendStatus(); sendMotor();
}
void ok(const char* c) { txPush("OK,%s", c); }
void er(const char* c, const char* why) { txPush("ERR,%s,%s", c, why); }

void handleCmd(char* line, uint32_t now) {
  char* sp = nullptr;
  char* cmd = strtok_r(line, " ,\r\n", &sp);
  if (!cmd) return;
  for (char* c = cmd; *c; c++) *c = toupper((unsigned char)*c);
  char* tok[16]; int n = 0;
  while (n < 16 && (tok[n] = strtok_r(nullptr, " ,\r\n", &sp))) n++;
  bool running = (st == S_RUN || st == S_PAUSE_MAN || st == S_PAUSE_LOCK);

  // ---- perintah aman: tanpa AUTH ----
  if (!strcmp(cmd, "EMERG")) { emergencyOff(); ok(cmd); return; }
  if (!strcmp(cmd, "STOP")) {
    if (running) stopAndDrain(now);
    else if (st == S_TEST) { drvStop(); motorStop(); digitalWrite(PIN_RELAY_SOAP, LOW); soapOn = false; goOff(); }
    else if (st == S_SELECT || st == S_FAULT || st == S_DONE) { BEEP(P_PRESS); if (st == S_FAULT && lockOn) stopAndDrain(now); else goOff(); }
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
    if (a < 1 || a > NPROG) { er(cmd, "arg"); return; }
    if (st == S_OFF) { ringIdx = a; powerOn(now); BEEP(P_POWERON); ok(cmd); }
    else if (st == S_SELECT) { ringIdx = a; idleT = now; BEEP(P_TICK); ok(cmd); }
    else er(cmd, "busy");
    return;
  }
  if (!strcmp(cmd, "START")) {
    if (!cfg.remoteStart) { er(cmd, "remote_start_off"); return; }
    if (st != S_SELECT || ringIdx == 0) { er(cmd, "not_selected"); return; }
    if (startRun(now)) ok(cmd); else er(cmd, "motor_or_plan");
    return;
  }
  if (!strcmp(cmd, "PAUSE")) { if (st == S_RUN) { pauseRun(S_PAUSE_MAN, now); ok(cmd); } else er(cmd, "state"); return; }
  if (!strcmp(cmd, "RESUME")) {
    if ((st == S_PAUSE_MAN || st == S_PAUSE_LOCK) && (doorLocked || !lockOn)) { resumeRun(now); ok(cmd); } else er(cmd, "state_or_door");
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
    cfgDirty = true;
    if (!strcasecmp(q->key, "mot_s") || !strcasecmp(q->key, "mot_k")) buildTables(cfg.motS ? -1 : 1, cfg.motK);
    ok(cmd); return;
  }
  if (!strcmp(cmd, "PSET")) {
    if (n < 11) { er(cmd, "arg"); return; }
    if (!idleState()) { er(cmd, "busy"); return; }
    int i = atoi(tok[0]); if (i < 1 || i > NPROG) { er(cmd, "arg"); return; }
    long v[10]; for (int k = 0; k < 10; k++) v[k] = atol(tok[k + 1]);
    for (int k = 0; k < 10; k++) { long mx = (k == 8) ? 65535 : 255; if (v[k] < 0 || v[k] > mx) { er(cmd, "range"); return; } }
    WProg old = cfg.prog[i - 1]; WProg& p = cfg.prog[i - 1];
    p.cycles = v[0]; p.washMin = v[1]; p.rinses = v[2]; p.rinseMin = v[3]; p.spinMin = v[4]; p.onS = v[5]; p.offS = v[6]; p.tumbleRpm = v[7]; p.spinRpm = v[8]; p.soapS = v[9];
    if (!cfgSane()) { cfg.prog[i - 1] = old; er(cmd, "constraint"); return; }
    cfgDirty = true; ok(cmd); return;
  }
  if (!strcmp(cmd, "RING")) {
    if (n < NPROG) { er(cmd, "arg"); return; }
    if (!idleState()) { er(cmd, "busy"); return; }
    uint8_t old[NPROG]; memcpy(old, cfg.ring, NPROG);
    for (int k = 0; k < NPROG; k++) cfg.ring[k] = (uint8_t)atoi(tok[k]);
    if (!cfgSane()) { memcpy(cfg.ring, old, NPROG); er(cmd, "constraint"); return; }
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
  if (!strcmp(cmd, "SAVE")) {
    if (!idleState()) { er(cmd, "busy"); return; }
    if (cfgSave()) { cfgDirty = false; ok(cmd); } else er(cmd, "flash");
    return;
  }
  if (!strcmp(cmd, "LOAD")) { if (!idleState()) { er(cmd, "busy"); return; } cfgLoad(); buildTables(cfg.motS ? -1 : 1, cfg.motK); ok(cmd); return; }
  if (!strcmp(cmd, "DEFAULTS")) {
    if (!idleState()) { er(cmd, "busy"); return; }
    uint32_t pin = cfg.pin; char nm[24]; memcpy(nm, cfg.name, 24); uint8_t ms = cfg.motS, mk = cfg.motK, mo = cfg.motOk;
    cfgDefaults(); cfg.pin = pin; memcpy(cfg.name, nm, 24); cfg.motS = ms; cfg.motK = mk; cfg.motOk = mo;
    cfgSave(); cfgDirty = false; ok(cmd); return;
  }
  if (!strcmp(cmd, "MLEARN")) {
    if (!(st == S_OFF || st == S_SELECT)) { er(cmd, "busy"); return; }
    testStart(1, now); ok(cmd); return;
  }
  if (!strcmp(cmd, "MTEST")) {
    if (n < 3) { er(cmd, "arg"); return; }
    if (!(st == S_OFF || st == S_SELECT)) { er(cmd, "busy"); return; }
    if (!cfg.motOk) { er(cmd, "not_learned"); return; }
    int d = atoi(tok[0]); float r = atof(tok[1]); int s = atoi(tok[2]);
    if (d < 0 || d > 1 || r < 20 || r > 250 || s < 3 || s > 30) { er(cmd, "range"); return; }
    testDir = d; testRpm = r; testStart(2, now); testEnd = (uint32_t)s * 1000UL; ok(cmd); return;
  }
  if (!strcmp(cmd, "SOAP")) {
    if (n < 1) { er(cmd, "arg"); return; }
    if (!(st == S_OFF || st == S_SELECT)) { er(cmd, "busy"); return; }
    int s = atoi(tok[0]); if (s < 1 || s > 30) { er(cmd, "range"); return; }
    testStart(3, now); testEnd = now + (uint32_t)s * 1000UL; ok(cmd); return;
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
  if (bleConn && ((uint8_t)st != lastSt || now - tS >= 1000)) { tS = now; sendStatus(); sendMotor(); }
  lastSt = (uint8_t)st;
  txPump(now);
}

// ===================== MODE UJI HARDWARE (tahan knob saat power-on) =====================
void runTestMode() {
  const char* names[5] = {"RLY1 ISI AIR", "RLY2 BUANG", "RLY3 KUNCI", "RLY4 SABUN", "BUZZER"};
  const uint8_t pins[5] = {PIN_RELAY_FILL, PIN_RELAY_DRAIN, PIN_RELAY_LOCK, PIN_RELAY_SOAP, PIN_BUZZER};
  bool on[5] = {false, false, false, false, false};
  uint8_t sel = 0; bool prevUp = false; char b[28];
  uint32_t t0 = millis(), tUi = 0, tDoor = 0, lastBtn = 0;
  oledPower(true);
  while (true) {
    uint32_t now = millis(); esp_task_wdt_reset();
    if (now - tDoor >= 2) { tDoor = now; doorSample(now); levelSample(now); }
    int8_t d = encRead();
    if (d) { sel = (sel + 5 + (d > 0 ? 1 : -1)) % 5; t0 = now; }
    bool up = digitalRead(PIN_ENC_SW) == HIGH && digitalRead(PIN_START) == HIGH;
    if (!up && prevUp && now - lastBtn > 200) { lastBtn = now; on[sel] = !on[sel]; digitalWrite(pins[sel], on[sel]); t0 = now; }
    prevUp = up;
    if (now - t0 > 300000UL) { for (int i = 0; i < 5; i++) digitalWrite(pins[i], LOW); ESP.restart(); }
    if (now - tUi >= 150) {
      tUi = now; oled.clearDisplay(); oled.setTextColor(SSD1306_WHITE);
      txt(0, 0, 1, "MODE UJI - LEPAS BEBAN");
      sprintf(b, "> %s: %s", names[sel], on[sel] ? "ON" : "OFF"); txt(0, 12, 1, b);
      sprintf(b, "KUNCI: %s  LEVEL: %s", doorLocked ? "TERKUNCI" : "BUKA", lvlRaw ? "PENUH" : "KOSONG"); txt(0, 26, 1, b);
      sprintf(b, "HALL: %u  EDGE: %lu", (unsigned)readHall(), (unsigned long)hallEdges); txt(0, 38, 1, b);
      sprintf(b, "IPM: %s", digitalRead(PIN_FAULT) == HIGH ? "OK" : "FAULT"); txt(0, 50, 1, b);
      oled.display();
    }
  }
}

// ===================== SETUP & LOOP =====================
void setup() {
  const uint8_t outs[] = {PIN_RELAY_FILL, PIN_RELAY_DRAIN, PIN_RELAY_LOCK, PIN_RELAY_SOAP, PIN_BUZZER};
  for (uint8_t i = 0; i < sizeof(outs); i++) { pinMode(outs[i], OUTPUT); digitalWrite(outs[i], LOW); }
  for (int i = 0; i < 3; i++) { pinMode(LO_PIN[i], OUTPUT); digitalWrite(LO_PIN[i], LOW); }   // saklar bawah IPM OFF secepat mungkin
  pinMode(PIN_ENC_CLK, INPUT_PULLUP); pinMode(PIN_ENC_DT, INPUT_PULLUP); pinMode(PIN_ENC_SW, INPUT_PULLUP); pinMode(PIN_START, INPUT_PULLUP);
  pinMode(PIN_DOOR, INPUT); pinMode(PIN_LEVEL, INPUT); pinMode(PIN_FAULT, INPUT);
  pinMode(HALL_A, INPUT); pinMode(HALL_B, INPUT); pinMode(HALL_C, INPUT);
  cfgLoad();
  lastRing = ringIdx = cfg.ring[0];
  drvInit();
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  esp_task_wdt_config_t wc = {8000, 0, true}; esp_task_wdt_reconfigure(&wc);
#else
  esp_task_wdt_init(8, true);
#endif
  esp_task_wdt_add(NULL);
  Wire.begin(PIN_SDA, PIN_SCL); Wire.setClock(400000);
  oled.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR); oled.clearDisplay(); oled.display(); oledOn = true; oledPower(false);
  lastLowMs = millis() - 1000; lastLvlLowMs = millis() - 1000;
  if (digitalRead(PIN_ENC_SW) == LOW) runTestMode();     // tidak kembali
  bleInit();
}

void loop() {
  uint32_t now = millis(); esp_task_wdt_reset();
  static uint32_t tUi = 0, tDoor = 0; static bool lastDoor = false;
  if (now - tDoor >= 2) { tDoor = now; doorSample(now); levelSample(now); }
  motorTick(now);
  ipmFaultCheck(now);

  // ---- jam program: berjalan hanya saat RUN dan bukan menunggu kunci ----
  if (st == S_RUN && sub != SB_LOCK) {
    runMs += now - lastTick; lastTick = now;
    if (runMs > plan[planI].endMs && stageIncomplete()) runMs = plan[planI].endMs;       // tahan jam sampai isi/buang air selesai
    if (runMs >= plan[planI].endMs && !stageIncomplete()) {
      if (++planI >= planN) { runMs = totalMs; finishRun(now); } else beginStage(now);
    }
  } else lastTick = now;

  if (st == S_RUN && sub != SB_LOCK && lockOn && !doorLocked) pauseRun(S_PAUSE_LOCK, now);   // kontak kunci hilang -> JEDA
  if (st == S_RUN) washTick(now);

  if (st == S_PAUSE_MAN) {
    if (lockOn && motorStopped() && levelEmptyStable(now, 3000)) setLock(false);          // kunci dilepas hanya jika drum diam dan tidak ada air
    if (now - stateT > PAUSE_TIMEOUT_MS) stopAndDrain(now);
  }
  if (st == S_PAUSE_LOCK) {
    if (doorLocked) {
      if (bzLoop) beepStop();
      if (!lastDoor) doorClosedAt = now;
      if (cfg.doorAutoResume && now - doorClosedAt >= DOOR_RESUME_MS) resumeRun(now);
    } else if (!bz) beepPattern(P_WARN, 1, true);
    if (st == S_PAUSE_LOCK && now - stateT > PAUSE_TIMEOUT_MS) stopAndDrain(now);
  }
  lastDoor = doorLocked;

  if (st == S_STOPDRAIN) {
    if (lvlRaw) sawWater = true;
    bool empty = levelEmptyStable(now, 2000);
    if (!empty) { setDrain(true); emptySince = 0; }
    else {
      if (!emptySince) emptySince = now;
      if (!sawWater || now - emptySince >= (uint32_t)cfg.drainExtra * 1000UL) { setDrain(false); if (motorStopped()) goOff(); }
      else setDrain(true);
    }
    if (st == S_STOPDRAIN && !empty && now - drainT0 > (uint32_t)cfg.drainTimeout * 1000UL) doFault(6);
  }
  if (st == S_FAULT) {
    static uint32_t tFb = 0; if (now - tFb > 10000UL) { tFb = now; BEEP(P_FAULT); }
    if (lockOn && motorStopped() && levelEmptyStable(now, 3000)) setLock(false);          // buka kunci hanya jika aman (tanpa air)
  }
  if (st == S_DONE) {
    if (lockOn && motorStopped()) setLock(false);
    if ((now - stateT >= DONE_SHOW_MS && !lockOn) || now - stateT > 90000UL) goOff();
  }
  if (st == S_TEST) testTick(now);
  if (st == S_SELECT && now - idleT >= SELECT_IDLE_MS) { BEEP(P_PRESS); goOff(); }

  // ---- pengaman umum ----
  if (!doorLocked) { if (fillOn) setFill(false); if (soapOn && st != S_TEST) setSoap(false); if (motorRun) motorStop(); }
  if (st == S_OFF && (fillOn || drainOn || soapOn || motorRun || lockOn)) allOff();

  int8_t d = encRead(); if (d) onTurn(d, now);
  buttonTick(now);
  bleTick(now);
  buzzerTick(now);
  if (now - tUi >= 150) { tUi = now; if (st != S_OFF) drawUI(now, (btnDown && (st == S_RUN || st == S_PAUSE_MAN || st == S_PAUSE_LOCK)) ? now - btnAt : 0); }
}
