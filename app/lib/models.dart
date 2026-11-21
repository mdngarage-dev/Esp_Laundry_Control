/// Satu baris status "S," dari ESP32 (18 kolom termasuk huruf S).
class MachineStatus {
  final int state, prog, remainS, totalS, temp10, raw10, ohm, heat, fault, retries;
  final bool gas, ign, motor, door, sensorOk, cooling, dirty;

  const MachineStatus({
    required this.state, required this.prog, required this.remainS, required this.totalS,
    required this.temp10, required this.raw10, required this.ohm, required this.heat,
    required this.fault, required this.retries, required this.gas, required this.ign,
    required this.motor, required this.door, required this.sensorOk, required this.cooling,
    required this.dirty,
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

  /// Sama dengan idleState() di firmware: setting hanya boleh dikirim di state ini.
  bool get canEdit => state == 0 || state == 1 || state == 6 || state == 7;

  String get stateText {
    const t = ['MATI', 'PILIH PROGRAM', 'BERJALAN', 'DIJEDA', 'PINTU TERBUKA', 'STOP - PENDINGINAN', 'SELESAI', 'ERROR'];
    return state >= 0 && state < t.length ? t[state] : '?';
  }
}

class ProgramCfg {
  final String name;
  final int minutes, heat, onS, offS, tCut, coolS;
  const ProgramCfg({required this.name, required this.minutes, required this.heat,
      required this.onS, required this.offS, required this.tCut, required this.coolS});

  ProgramCfg copyWith({int? minutes, int? heat, int? onS, int? offS, int? tCut, int? coolS}) => ProgramCfg(
        name: name, minutes: minutes ?? this.minutes, heat: heat ?? this.heat, onS: onS ?? this.onS,
        offS: offS ?? this.offS, tCut: tCut ?? this.tCut, coolS: coolS ?? this.coolS);

  bool same(ProgramCfg o) => minutes == o.minutes && heat == o.heat && onS == o.onS && offS == o.offS && tCut == o.tCut && coolS == o.coolS;

  Map<String, dynamic> toJson() => {'n': name, 'm': minutes, 'h': heat, 'on': onS, 'off': offS, 't': tCut, 'c': coolS};
  factory ProgramCfg.fromJson(Map<String, dynamic> j) => ProgramCfg(
      name: j['n'] as String, minutes: j['m'] as int, heat: j['h'] as int, onS: j['on'] as int,
      offS: j['off'] as int, tCut: j['t'] as int, coolS: j['c'] as int);
}

const List<ProgramCfg> kDefaultPrograms = [
  ProgramCfg(name: '30 MINS', minutes: 30, heat: 1, onS: 240, offS: 90, tCut: 68, coolS: 300),
  ProgramCfg(name: '1 JAM', minutes: 60, heat: 1, onS: 240, offS: 90, tCut: 68, coolS: 480),
  ProgramCfg(name: '2 JAM', minutes: 120, heat: 1, onS: 240, offS: 90, tCut: 68, coolS: 480),
  ProgramCfg(name: '2,5 JAM', minutes: 150, heat: 1, onS: 240, offS: 90, tCut: 68, coolS: 480),
  ProgramCfg(name: 'AIRING', minutes: 30, heat: 0, onS: 0, offS: 0, tCut: 0, coolS: 0),
  ProgramCfg(name: 'JEANS', minutes: 60, heat: 1, onS: 330, offS: 60, tCut: 70, coolS: 360),
  ProgramCfg(name: 'IRON DRY', minutes: 60, heat: 1, onS: 420, offS: 45, tCut: 72, coolS: 180),
  ProgramCfg(name: 'TOWELS', minutes: 30, heat: 1, onS: 90, offS: 150, tCut: 60, coolS: 480),
  ProgramCfg(name: 'EXTRA DRY', minutes: 65, heat: 1, onS: 240, offS: 90, tCut: 68, coolS: 480),
];

/// Urutan knob bawaan: putar kanan dari OFF = EXTRA DRY (9), lalu TOWELS (8), ... , 30 MINS (1).
const List<int> kDefaultRing = [9, 8, 7, 6, 5, 4, 3, 2, 1];
