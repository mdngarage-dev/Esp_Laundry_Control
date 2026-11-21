import 'models.dart';

/// Nilai milik perangkat: hanya diubah saat terhubung (kalibrasi / PIN), tidak ikut sinkronisasi massal.
const Set<String> kDeviceOwned = {'ntc_off', 'ntc_beta', 'pin'};

class ParamMeta {
  const ParamMeta(this.key, this.title, this.group,
      {this.unit = '', this.min = 0, this.max = 1, this.isInt = true, this.isBool = false, this.note});
  final String key, title, group, unit;
  final double min, max;
  final bool isInt, isBool;
  final String? note;
}

/// Parameter yang bisa diedit offline (draft) lalu disinkron. Batas HARUS sama dengan tabel PARAMS di firmware.
const List<ParamMeta> kParamMeta = [
  ParamMeta('door_resume', 'Lanjut otomatis setelah pintu ditutup', 'Pintu', isBool: true,
      note: 'Mati = harus tekan LANJUT (di HP atau knob di mesin)'),
  ParamMeta('remote_start', 'Izinkan mulai dari HP', 'Keamanan', isBool: true,
      note: 'Mati = pilih program dari HP, mulai dengan menekan knob di mesin'),
  ParamMeta('ign_warm', 'Igniter memanas sebelum gas', 'Siklus gas dan pengaman', unit: 'detik', min: 20, max: 90),
  ParamMeta('prestart', 'Tunda awal setelah motor ON', 'Siklus gas dan pengaman', unit: 'detik', min: 5, max: 60),
  ParamMeta('proof', 'Batas waktu pembuktian api', 'Siklus gas dan pengaman', unit: 'detik', min: 15, max: 60),
  ParamMeta('proof_rise', 'Kenaikan suhu bukti api', 'Siklus gas dan pengaman', unit: '°C', min: 0.5, max: 10, isInt: false),
  ParamMeta('purge', 'Jeda purge setelah gagal nyala', 'Siklus gas dan pengaman', unit: 'detik', min: 30, max: 300),
  ParamMeta('retry', 'Jumlah coba ulang nyala', 'Siklus gas dan pengaman', unit: 'x', min: 0, max: 3),
  ParamMeta('hyst', 'Histeresis (gas nyala lagi di tCut dikurangi ini)', 'Siklus gas dan pengaman', unit: '°C', min: 2, max: 20, isInt: false),
  ParamMeta('t_hard', 'Batas error suhu terlalu panas', 'Siklus gas dan pengaman', unit: '°C', min: 50, max: 90, isInt: false),
  ParamMeta('ign_off_proof', 'Matikan igniter setelah api terbukti', 'Siklus gas dan pengaman', isBool: true,
      note: 'Aktifkan hanya jika igniter bukan tipe yang harus menyala terus'),
  ParamMeta('stopcool_s', 'Pendinginan maksimal', 'Tombol STOP', unit: 'detik', min: 30, max: 600),
  ParamMeta('stopcool_t', 'Selesai pendinginan di bawah', 'Tombol STOP', unit: '°C', min: 30, max: 60),
];

const Map<String, String> kDefaultParams = {
  'door_resume': '1', 'remote_start': '0', 'retry': '1', 'ign_off_proof': '0', 'stopcool_t': '45',
  'ign_warm': '40', 'prestart': '10', 'proof': '40', 'purge': '60', 'stopcool_s': '180',
  'ntc_off': '0.00', 'ntc_beta': '3950.00', 't_hard': '80.00', 'hyst': '7.00', 'proof_rise': '2.00',
};

String fmtNum(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

bool sameNum(String? a, String? b) {
  final x = double.tryParse(a ?? ''), y = double.tryParse(b ?? '');
  if (x == null || y == null) return a == b;
  return (x - y).abs() < 0.005;
}

/// Cermin cfgSane() di firmware: tolak draft yang akan ditolak mesin saat sinkron.
String? checkDraft(Map<String, String> p, List<ProgramCfg> progs) {
  final tHard = double.tryParse(p['t_hard'] ?? '') ?? 80;
  final hyst = double.tryParse(p['hyst'] ?? '') ?? 7;
  for (final q in progs) {
    if (q.minutes < 5 || q.minutes > 240) return '${q.name}: durasi harus 5-240 menit';
    if (q.heat == 1) {
      if (q.onS < 30 || q.onS > 900) return '${q.name}: gas nyala harus 30-900 detik';
      if (q.offS < 10 || q.offS > 900) return '${q.name}: gas mati harus 10-900 detik';
      if (q.coolS > 900) return '${q.name}: pendinginan maksimal 900 detik';
      if (q.tCut < 40) return '${q.name}: tCut minimal 40 °C';
      if (q.tCut + 5 > tHard) return '${q.name}: tCut harus ≤ batas error (${fmtNum(tHard)}) dikurangi 5';
      if (q.tCut - hyst < 30) return '${q.name}: tCut dikurangi histeresis harus ≥ 30 °C';
    }
  }
  return null;
}

/// Nama harus ASCII biasa tanpa koma (firmware menyimpan maks 23 karakter).
String? nameError(String n) {
  final t = n.trim();
  if (t.isEmpty) return 'Nama tidak boleh kosong';
  if (t.length > 23) return 'Maksimal 23 karakter';
  for (final u in t.codeUnits) {
    if (u < 0x20 || u > 0x7E || u == 0x2C) return 'Hanya huruf, angka, dan spasi biasa (tanpa koma / karakter khusus)';
  }
  return null;
}

String normName(String n) => n.trim().replaceAll(RegExp(r'\s+'), ' ');
