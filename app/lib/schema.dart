import 'models.dart';

class ParamMeta {
  const ParamMeta(this.key, this.title, this.group,
      {this.unit = '', this.min = 0, this.max = 1, this.isInt = true, this.isBool = false, this.note});
  final String key, title, group, unit;
  final double min, max;
  final bool isInt, isBool;
  final String? note;
}

class FieldMeta {
  const FieldMeta(this.label, this.unit, this.min, this.max, {this.isBool = false});
  final String label, unit;
  final int min, max;
  final bool isBool;
}

/// Semua yang berbeda antara dryer dan mesin cuci: parameter, program, urutan knob, nilai default.
/// Nilai default HARUS sama dengan default di firmware (dryer_firmware_v3_2 / washer_firmware_v1_1).
class MachineSchema {
  MachineSchema({required this.type, required this.title, required this.params, required this.defParams,
      required this.deviceOwned, required this.progNames, required this.fields, required this.defProgs,
      required this.defRing, required this.check, required this.summary});
  final String type, title;
  final List<ParamMeta> params;
  final Map<String, String> defParams;
  final Set<String> deviceOwned;
  final List<String> progNames;
  final List<FieldMeta> fields;
  final List<List<int>> defProgs;
  final List<int> defRing;
  final String? Function(Map<String, String>, List<ProgramCfg>) check;
  final String Function(ProgramCfg) summary;

  int get n => progNames.length;
  List<ProgramCfg> defaultPrograms() => [for (int i = 0; i < n; i++) ProgramCfg(progNames[i], List<int>.of(defProgs[i]))];
  ParamMeta? meta(String key) {
    for (final m in params) {
      if (m.key == key) return m;
    }
    return null;
  }
}

String fmtNum(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

bool sameNum(String? a, String? b) {
  final x = double.tryParse(a ?? ''), y = double.tryParse(b ?? '');
  if (x == null || y == null) return a == b;
  return (x - y).abs() < 0.005;
}

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

double _p(Map<String, String> p, String k, double d) => double.tryParse(p[k] ?? '') ?? d;

// ---------------------------------------------------------------- DRYER
const List<ParamMeta> _dryerParams = [
  ParamMeta('door_resume', 'Lanjut otomatis setelah pintu ditutup', 'Pintu', isBool: true, note: 'Mati = harus tekan LANJUT (di HP atau knob di mesin)'),
  ParamMeta('remote_start', 'Izinkan mulai dari HP', 'Keamanan', isBool: true, note: 'Mati = pilih program dari HP, mulai dengan menekan knob di mesin'),
  ParamMeta('order_req', 'Wajib scan barcode order dulu', 'Barcode order', isBool: true, note: 'Aktif = mesin baru bisa mulai setelah barcode order di-scan lewat aplikasi (berlaku juga untuk tombol di mesin)'),
  ParamMeta('order_ttl', 'Masa berlaku hasil scan', 'Barcode order', unit: 'detik', min: 60, max: 3600),
  ParamMeta('ign_warm', 'Igniter memanas sebelum gas', 'Panas dan siklus gas', unit: 'detik', min: 20, max: 90),
  ParamMeta('prestart', 'Tunda awal setelah motor ON', 'Panas dan siklus gas', unit: 'detik', min: 5, max: 60),
  ParamMeta('proof', 'Batas waktu pembuktian api', 'Panas dan siklus gas', unit: 'detik', min: 15, max: 60),
  ParamMeta('proof_rise', 'Kenaikan suhu bukti api', 'Panas dan siklus gas', unit: '°C', min: 0.5, max: 10, isInt: false),
  ParamMeta('purge', 'Jeda purge setelah gagal nyala', 'Panas dan siklus gas', unit: 'detik', min: 30, max: 300),
  ParamMeta('retry', 'Jumlah coba ulang nyala', 'Panas dan siklus gas', unit: 'x', min: 0, max: 3),
  ParamMeta('hyst', 'Histeresis (gas nyala lagi di tCut dikurangi ini)', 'Panas dan siklus gas', unit: '°C', min: 2, max: 20, isInt: false),
  ParamMeta('t_hard', 'Batas error suhu terlalu panas', 'Panas dan siklus gas', unit: '°C', min: 50, max: 90, isInt: false),
  ParamMeta('ign_off_proof', 'Matikan igniter setelah api terbukti', 'Panas dan siklus gas', isBool: true, note: 'Aktifkan hanya jika igniter bukan tipe yang harus menyala terus'),
  ParamMeta('stopcool_s', 'Pendinginan maksimal saat STOP', 'Tombol STOP', unit: 'detik', min: 30, max: 600),
  ParamMeta('stopcool_t', 'Selesai pendinginan di bawah', 'Tombol STOP', unit: '°C', min: 30, max: 60),
  ParamMeta('select_idle', 'Layar pilihan mati otomatis setelah', 'Waktu mesin', unit: 'detik', min: 30, max: 600),
  ParamMeta('pause_timeout', 'Jeda terlalu lama, mesin OFF setelah', 'Waktu mesin', unit: 'detik', min: 60, max: 3600),
  ParamMeta('done_show', 'Tampilan SELESAI sebelum OFF', 'Waktu mesin', unit: 'detik', min: 3, max: 60),
];

const Map<String, String> _dryerDef = {
  'door_resume': '1', 'remote_start': '0', 'retry': '1', 'ign_off_proof': '0', 'stopcool_t': '45',
  'ign_warm': '40', 'prestart': '10', 'proof': '40', 'purge': '60', 'stopcool_s': '180',
  'ntc_off': '0.00', 'ntc_beta': '3950.00', 't_hard': '80.00', 'hyst': '7.00', 'proof_rise': '2.00',
  'select_idle': '60', 'pause_timeout': '600', 'done_show': '8', 'order_req': '0', 'order_ttl': '600',
};

String? _dryerCheck(Map<String, String> p, List<ProgramCfg> progs) {
  final tHard = _p(p, 't_hard', 80), hyst = _p(p, 'hyst', 7);
  for (final q in progs) {
    final v = q.v;
    if (v[0] < 5 || v[0] > 240) return '${q.name}: durasi harus 5-240 menit';
    if (v[1] == 1) {
      if (v[2] < 30 || v[2] > 900) return '${q.name}: gas nyala harus 30-900 detik';
      if (v[3] < 10 || v[3] > 900) return '${q.name}: gas mati harus 10-900 detik';
      if (v[5] > 900) return '${q.name}: pendinginan maksimal 900 detik';
      if (v[4] < 40) return '${q.name}: suhu potong minimal 40 °C';
      if (v[4] + 5 > tHard) return '${q.name}: suhu potong harus ≤ batas error (${fmtNum(tHard)}) dikurangi 5';
      if (v[4] - hyst < 30) return '${q.name}: suhu potong dikurangi histeresis harus ≥ 30 °C';
    }
  }
  return null;
}

final MachineSchema dryerSchema = MachineSchema(
  type: 'dryer', title: 'Dryer', params: _dryerParams, defParams: _dryerDef,
  deviceOwned: {'ntc_off', 'ntc_beta', 'pin'},
  progNames: const ['30 MINS', '1 JAM', '2 JAM', '2,5 JAM', 'AIRING', 'JEANS', 'IRON DRY', 'TOWELS', 'EXTRA DRY'],
  fields: const [
    FieldMeta('Durasi total', 'menit', 5, 240),
    FieldMeta('Pakai gas + igniter', '', 0, 1, isBool: true),
    FieldMeta('Gas nyala', 'detik', 30, 900),
    FieldMeta('Gas mati', 'detik', 10, 900),
    FieldMeta('Suhu potong (panas)', '°C', 40, 85),
    FieldMeta('Pendinginan akhir maks', 'detik', 0, 900),
  ],
  defProgs: const [
    [30, 1, 240, 90, 68, 300], [60, 1, 240, 90, 68, 480], [120, 1, 240, 90, 68, 480], [150, 1, 240, 90, 68, 480],
    [30, 0, 0, 0, 0, 0], [60, 1, 330, 60, 70, 360], [60, 1, 420, 45, 72, 180], [30, 1, 90, 150, 60, 480], [65, 1, 240, 90, 68, 480],
  ],
  defRing: const [9, 8, 7, 6, 5, 4, 3, 2, 1],
  check: _dryerCheck,
  summary: (p) => p.v[1] == 0
      ? '${p.v[0]} menit  •  angin saja (tanpa gas)'
      : '${p.v[0]} menit  •  gas ${p.v[2]}s nyala / ${p.v[3]}s mati  •  potong ${p.v[4]}°C  •  dingin akhir ${p.v[5]}s',
);

// ---------------------------------------------------------------- MESIN CUCI
const List<ParamMeta> _washerParams = [
  ParamMeta('door_resume', 'Lanjut otomatis setelah kunci kembali', 'Pintu dan kunci', isBool: true, note: 'Dipakai saat kontak kunci hilang di tengah proses'),
  ParamMeta('lock_wait', 'Batas waktu menunggu kunci terkunci', 'Pintu dan kunci', unit: 'detik', min: 10, max: 90),
  ParamMeta('remote_start', 'Izinkan mulai dari HP', 'Keamanan', isBool: true, note: 'Mati = pilih program dari HP, mulai dengan menekan knob di mesin'),
  ParamMeta('order_req', 'Wajib scan barcode order dulu', 'Barcode order', isBool: true, note: 'Aktif = mesin baru bisa mulai setelah barcode order di-scan lewat aplikasi (berlaku juga untuk tombol di mesin)'),
  ParamMeta('order_ttl', 'Masa berlaku hasil scan', 'Barcode order', unit: 'detik', min: 60, max: 3600),
  ParamMeta('soap_en', 'Pakai pompa sabun otomatis', 'Sabun', isBool: true, note: 'Mati = tahap sabun dilewati, mesin tetap jalan normal. Lama pompa per program diatur di menu Program.'),
  ParamMeta('fill_timeout', 'Batas waktu isi air (error E5)', 'Air', unit: 'detik', min: 30, max: 600, note: 'Mesin hanya tahu "level penuh". Isi dengan waktu isi normal x 1,5.'),
  ParamMeta('drain_timeout', 'Batas waktu buang air (error E6)', 'Air', unit: 'detik', min: 60, max: 900),
  ParamMeta('drain_extra', 'Pompa buang tambahan setelah level kosong', 'Air', unit: 'detik', min: 5, max: 120),
  ParamMeta('spin_hi_min', 'Peras kencang mulai saat sisa waktu', 'Peras dan keseimbangan', unit: 'menit', min: 4, max: 12),
  ParamMeta('spin_fin_min', 'Melambat saat sisa waktu', 'Peras dan keseimbangan', unit: 'menit', min: 1, max: 4),
  ParamMeta('drain_rpm', 'Putaran pelan saat membuang air', 'Peras dan keseimbangan', unit: 'rpm', min: 0, max: 200),
  ParamMeta('balance_rpm', 'Putaran untuk cek keseimbangan', 'Peras dan keseimbangan', unit: 'rpm', min: 50, max: 300),
  ParamMeta('finish_rpm', 'Putaran saat hampir selesai', 'Peras dan keseimbangan', unit: 'rpm', min: 0, max: 200),
  ParamMeta('bal_hold_s', 'Lama pengukuran keseimbangan', 'Peras dan keseimbangan', unit: 'detik', min: 4, max: 30),
  ParamMeta('redist_s', 'Lama meratakan beban', 'Peras dan keseimbangan', unit: 'detik', min: 6, max: 60),
  ParamMeta('unbal_pct', 'Batas riak (beban tidak seimbang)', 'Peras dan keseimbangan', unit: '%', min: 5, max: 80, isInt: false),
  ParamMeta('unbal_retry', 'Percobaan meratakan beban', 'Peras dan keseimbangan', unit: 'x', min: 0, max: 5),
  ParamMeta('unbal_abort', 'Berhenti error E4 jika tetap tidak seimbang', 'Peras dan keseimbangan', isBool: true, note: 'Mati = lanjut peras dengan putaran rendah + peringatan'),
  ParamMeta('slow_on_s', 'Putar pelan (buang air): lama putar', 'Peras dan keseimbangan', unit: 'detik', min: 3, max: 30),
  ParamMeta('slow_off_s', 'Putar pelan (buang air): jeda', 'Peras dan keseimbangan', unit: 'detik', min: 1, max: 15),
  ParamMeta('hall_per_rev', 'Hitungan Hall per putaran drum', 'Motor (tuning)', unit: 'edge', min: 6, max: 2000, note: 'Ukur di menu Kalibrasi motor'),
  ParamMeta('duty_start', 'Tenaga awal motor', 'Motor (tuning)', unit: '‰', min: 20, max: 300),
  ParamMeta('duty_max', 'Tenaga maksimal motor', 'Motor (tuning)', unit: '‰', min: 100, max: 950),
  ParamMeta('accel', 'Laju naik/turun putaran', 'Motor (tuning)', unit: 'rpm/s', min: 5, max: 400),
  ParamMeta('kp', 'Penguat P kecepatan', 'Motor (tuning)', min: 0.05, max: 5, isInt: false),
  ParamMeta('ki', 'Penguat I kecepatan', 'Motor (tuning)', min: 0.05, max: 10, isInt: false),
  ParamMeta('stall_s', 'Batas waktu tanpa Hall (motor macet)', 'Motor (tuning)', unit: 'detik', min: 1, max: 10),
  ParamMeta('learn_duty', 'Tenaga saat belajar motor', 'Motor (tuning)', unit: '‰', min: 20, max: 200),
  ParamMeta('dir_invert', 'Balik arah putar', 'Motor (tuning)', isBool: true),
  ParamMeta('select_idle', 'Layar pilihan mati otomatis setelah', 'Waktu mesin', unit: 'detik', min: 30, max: 600),
  ParamMeta('pause_timeout', 'Jeda terlalu lama, mesin berhenti setelah', 'Waktu mesin', unit: 'detik', min: 60, max: 3600),
  ParamMeta('done_show', 'Tampilan SELESAI sebelum OFF', 'Waktu mesin', unit: 'detik', min: 3, max: 60),
];

const Map<String, String> _washerDef = {
  'door_resume': '1', 'remote_start': '0', 'soap_en': '1', 'unbal_retry': '3', 'unbal_abort': '0', 'dir_invert': '0',
  'mot_s': '0', 'mot_k': '0', 'mot_ok': '0', 'fill_timeout': '60', 'drain_timeout': '240', 'drain_extra': '25',
  'lock_wait': '30', 'hall_per_rev': '144', 'duty_start': '60', 'duty_max': '600', 'accel': '40', 'drain_rpm': '40',
  'balance_rpm': '90', 'finish_rpm': '60', 'learn_duty': '70', 'stall_s': '3', 'kp': '0.80', 'ki': '1.50',
  'unbal_pct': '30.00', 'spin_hi_min': '8', 'spin_fin_min': '2', 'redist_s': '16', 'bal_hold_s': '9', 'slow_on_s': '8',
  'slow_off_s': '3', 'select_idle': '60', 'pause_timeout': '600', 'done_show': '8', 'order_req': '0', 'order_ttl': '600',
};

String? _washerCheck(Map<String, String> p, List<ProgramCfg> progs) {
  final hi = _p(p, 'spin_hi_min', 8), fin = _p(p, 'spin_fin_min', 2);
  if (fin + 1 >= hi) return 'Melambat harus lebih kecil dari mulai peras kencang (minimal selisih 2 menit)';
  for (final q in progs) {
    final v = q.v; // cycles, wash, rinses, rinseMin, spin, onS, offS, tumbleRpm, spinRpm, soapS
    if (v[0] < 1 || v[0] > 3) return '${q.name}: siklus harus 1-3';
    if (v[2] > 4) return '${q.name}: bilas maksimal 4';
    if (v[1] > 120 || v[3] > 60 || v[9] > 60) return '${q.name}: waktu cuci/bilas/sabun terlalu besar';
    if (v[1] > 0 && v[1] < 3) return '${q.name}: cuci minimal 3 menit (atau 0)';
    if (v[2] > 0 && v[3] < 5) return '${q.name}: waktu per bilas minimal 5 menit';
    if (v[4] > 0 && (v[4] < hi + 2 || v[4] > 40)) return '${q.name}: peras harus 0 atau ${fmtNum(hi + 2)}-40 menit';
    if (v[4] > 0 && (v[8] < 100 || v[8] > 1600)) return '${q.name}: putaran peras 100-1600 rpm';
    if (v[1] > 0 || v[2] > 0) {
      if (v[5] < 3 || v[5] > 60 || v[6] < 1 || v[6] > 30) return '${q.name}: putar 3-60 detik, jeda 1-30 detik';
      if (v[7] < 20 || v[7] > 120) return '${q.name}: putaran cuci 20-120 rpm';
    }
    final t = v[0] * (v[1] + v[2] * v[3] + v[4]);
    if (t < 5 || t > 480) return '${q.name}: total waktu harus 5-480 menit (sekarang $t)';
  }
  return null;
}

final MachineSchema washerSchema = MachineSchema(
  type: 'washer', title: 'Mesin Cuci', params: _washerParams, defParams: _washerDef,
  deviceOwned: {'mot_s', 'mot_k', 'mot_ok', 'pin'},
  progNames: const ['30 MINS', '60 MINS', 'RINSE SPIN', 'SPIN', 'COTTON', 'COTTON+', 'MIXED FABRIC', 'ALLERGY CARE',
    'ACTIVEWEAR', 'HAND/WOOL', 'DELICATES', 'TUBCLEAN'],
  fields: const [
    FieldMeta('Jumlah siklus (ulang)', 'x', 1, 3),
    FieldMeta('Waktu cuci (termasuk isi air)', 'menit', 0, 120),
    FieldMeta('Jumlah bilas', 'x', 0, 4),
    FieldMeta('Waktu tiap bilas', 'menit', 0, 60),
    FieldMeta('Waktu peras (0 = tanpa)', 'menit', 0, 40),
    FieldMeta('Putar bolak-balik: lama putar', 'detik', 0, 60),
    FieldMeta('Putar bolak-balik: jeda', 'detik', 0, 30),
    FieldMeta('Putaran cuci / bilas', 'rpm', 0, 120),
    FieldMeta('Putaran peras maksimal', 'rpm', 0, 1600),
    FieldMeta('Lama pompa sabun', 'detik', 0, 60),
  ],
  defProgs: const [
    [1, 10, 1, 10, 10, 12, 3, 45, 800, 6], [2, 10, 1, 10, 10, 12, 3, 45, 800, 6], [1, 0, 1, 10, 10, 12, 3, 45, 800, 0],
    [1, 0, 0, 0, 12, 0, 0, 0, 900, 0], [1, 30, 2, 12, 12, 12, 3, 50, 1000, 8], [1, 40, 3, 12, 14, 12, 3, 50, 1000, 8],
    [1, 20, 2, 10, 10, 10, 3, 40, 800, 6], [1, 40, 3, 15, 12, 12, 3, 45, 900, 8], [1, 15, 1, 10, 10, 10, 3, 40, 800, 6],
    [1, 15, 1, 10, 10, 6, 6, 30, 400, 5], [1, 15, 2, 8, 10, 8, 4, 35, 600, 5], [1, 40, 2, 10, 10, 12, 3, 55, 1000, 0],
  ],
  defRing: const [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 2],
  check: _washerCheck,
  summary: (p) {
    final t = p.v[0] * (p.v[1] + p.v[2] * p.v[3] + p.v[4]);
    return '$t menit  •  cuci ${p.v[1]}  •  bilas ${p.v[2]}x${p.v[3]}  •  peras ${p.v[4]} @${p.v[8]}rpm  •  sabun ${p.v[9]}s';
  },
);

MachineSchema schemaOf(String type) => type == 'washer' ? washerSchema : dryerSchema;
