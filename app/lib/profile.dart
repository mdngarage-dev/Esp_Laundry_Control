import 'defaults.dart';
import 'models.dart';

/// Data satu mesin yang disimpan di HP. params/programs/ring/name adalah DRAFT: boleh diedit offline,
/// baru dikirim ke ESP32 saat SYNC.
class MachineProfile {
  String id, type, name, pin;
  String? deviceId;
  Map<String, String> params;
  List<ProgramCfg> programs;
  List<int> ring;
  bool dirty; // ada perubahan draft yang belum disinkron
  bool fresh; // baru dipasangkan: ambil setting dari ESP kecuali nama

  MachineProfile({
    required this.id, required this.type, required this.name, this.deviceId, this.pin = '123456',
    Map<String, String>? params, List<ProgramCfg>? programs, List<int>? ring,
    this.dirty = false, this.fresh = false,
  })  : params = params ?? Map<String, String>.of(kDefaultParams),
        programs = programs ?? List<ProgramCfg>.of(kDefaultPrograms),
        ring = ring ?? List<int>.of(kDefaultRing);

  factory MachineProfile.create(String type, String name, {String? deviceId, String pin = '123456', bool fresh = false}) =>
      MachineProfile(
        id: DateTime.now().microsecondsSinceEpoch.toString(), type: type, name: name,
        deviceId: deviceId, pin: pin, dirty: !fresh, fresh: fresh,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, 'name': name, 'pin': pin, 'deviceId': deviceId, 'params': params,
        'programs': programs.map((p) => p.toJson()).toList(), 'ring': ring, 'dirty': dirty, 'fresh': fresh,
      };

  factory MachineProfile.fromJson(Map<String, dynamic> j) => MachineProfile(
        id: j['id'] as String, type: j['type'] as String, name: j['name'] as String,
        deviceId: j['deviceId'] as String?, pin: (j['pin'] as String?) ?? '123456',
        params: Map<String, String>.from(j['params'] as Map),
        programs: (j['programs'] as List).map((e) => ProgramCfg.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        ring: List<int>.from(j['ring'] as List),
        dirty: (j['dirty'] as bool?) ?? false, fresh: (j['fresh'] as bool?) ?? false,
      );
}
