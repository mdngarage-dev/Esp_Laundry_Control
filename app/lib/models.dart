/// Status dryer: baris "S," dari firmware dryer (18 kolom termasuk huruf S).
class MachineStatus {
  final int state, prog, remainS, totalS, temp10, raw10, ohm, heat, fault, retries;
  final bool gas, ign, motor, door, sensorOk, cooling, dirty;
  const MachineStatus({
    required this.state, required this.prog, required this.remainS, required this.totalS,
    required this.temp10, required this.raw10, required this.ohm, required this.heat,
    required this.fault, required this.retries, required this.gas, required this.ign,
    required this.motor, required this.door, required this.sensorOk, required this.cooling, required this.dirty,
  });

  static MachineStatus? parse(List<String> f) {
    if (f.length < 18) return null;
    int i(int k) => int.tryParse(f[k]) ?? 0;
    return MachineStatus(
      state: i(1), prog: i(2), remainS: i(3), totalS: i(4), temp10: i(5), raw10: i(6), ohm: i(7),
      heat: i(8), gas: i(9) == 1, ign: i(10) == 1, motor: i(11) == 1, door: i(12) == 1,
      fault: i(13), sensorOk: i(14) == 1, cooling: i(15) == 1, retries: i(16), dirty: i(17) == 1,
    );
  }

  double get temp => temp10 / 10.0;
  double get raw => raw10 / 10.0;
  bool get running => state >= 2 && state <= 5;
  bool get canEdit => state == 0 || state == 1 || state == 6 || state == 7;
  String get stateText {
    const t = ['MATI', 'PILIH PROGRAM', 'BERJALAN', 'DIJEDA', 'PINTU TERBUKA', 'STOP - PENDINGINAN', 'SELESAI', 'ERROR'];
    return state >= 0 && state < t.length ? t[state] : '?';
  }
}

/// Status mesin cuci: baris "S," dari firmware mesin cuci (18 kolom termasuk huruf S).
class WasherStatus {
  final int state, prog, remainS, totalS, stage, rpm, fault, unbal;
  final bool lockContact, lockRelay, levelFull, fill, drain, soap, motor, learned, dirty;
  const WasherStatus({
    required this.state, required this.prog, required this.remainS, required this.totalS, required this.stage,
    required this.rpm, required this.fault, required this.unbal, required this.lockContact, required this.lockRelay,
    required this.levelFull, required this.fill, required this.drain, required this.soap, required this.motor,
    required this.learned, required this.dirty,
  });

  static WasherStatus? parse(List<String> f) {
    if (f.length < 18) return null;
    int i(int k) => int.tryParse(f[k]) ?? 0;
    return WasherStatus(
      state: i(1), prog: i(2), remainS: i(3), totalS: i(4), stage: i(5), rpm: i(6), lockContact: i(7) == 1,
      lockRelay: i(8) == 1, levelFull: i(9) == 1, fill: i(10) == 1, drain: i(11) == 1, soap: i(12) == 1,
      motor: i(13) == 1, fault: i(14), learned: i(15) == 1, unbal: i(16), dirty: i(17) == 1,
    );
  }

  bool get running => state >= 2 && state <= 5;
  bool get canEdit => state == 0 || state == 1 || state == 6 || state == 7;
  String get stateText {
    const t = ['MATI', 'PILIH PROGRAM', 'BERJALAN', 'DIJEDA', 'KUNCI TERLEPAS', 'STOP - BUANG AIR', 'SELESAI', 'ERROR', 'UJI'];
    return state >= 0 && state < t.length ? t[state] : '?';
  }

  String get stageText {
    const t = ['', 'Mengunci pintu', 'Memasukkan sabun', 'Mengisi air', 'Mencuci / membilas', 'Membuang air', 'Membuang air (peras)',
      'Meratakan beban', 'Meratakan beban', 'Menaikkan putaran', 'Memeras', 'Melambat, hampir selesai'];
    return stage >= 0 && stage < t.length ? t[stage] : '';
  }
}

/// Baris "M," dari firmware mesin cuci (diagnosa motor).
class MotorInfo {
  final double rpm, ripple;
  final int duty, hall, edges;
  final bool vfoOk;
  const MotorInfo(this.rpm, this.duty, this.edges, this.hall, this.ripple, this.vfoOk);
  static MotorInfo? parse(List<String> f) {
    if (f.length < 7) return null;
    return MotorInfo((int.tryParse(f[1]) ?? 0) / 10.0, int.tryParse(f[2]) ?? 0, int.tryParse(f[3]) ?? 0,
        int.tryParse(f[4]) ?? 0, (int.tryParse(f[5]) ?? 0) / 10.0, f[6] == '1');
  }
}

/// Satu program: nama + daftar angka (arti tiap angka ditentukan MachineSchema.fields).
class ProgramCfg {
  final String name;
  final List<int> v;
  const ProgramCfg(this.name, this.v);
  ProgramCfg withValues(List<int> nv) => ProgramCfg(name, List<int>.of(nv));
  bool same(ProgramCfg o) {
    if (v.length != o.v.length) return false;
    for (int i = 0; i < v.length; i++) {
      if (v[i] != o.v[i]) return false;
    }
    return true;
  }
  Map<String, dynamic> toJson() => {'n': name, 'v': v};
  factory ProgramCfg.fromJson(Map<String, dynamic> j) => ProgramCfg(j['n'] as String, List<int>.from(j['v'] as List));
}
