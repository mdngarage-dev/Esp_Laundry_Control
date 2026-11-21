import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'defaults.dart';
import 'models.dart';
import 'profile.dart';
import 'ui_helpers.dart';

final Guid kSvc = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
final Guid kRx = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e'); // app menulis ke sini
final Guid kTx = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e'); // ESP32 notify ke sini

enum LinkPhase { idle, connecting, authing, ready }

class Reply {
  final bool ok;
  final String info;
  const Reply(this.ok, this.info);
}

class _Pending {
  final String cmd;
  final String name;
  final bool expectReply;
  final Completer<Reply> c = Completer<Reply>();
  _Pending(this.cmd, this.expectReply) : name = cmd.split(' ').first.toUpperCase();
}

class _Op {
  final String cmd;
  final VoidCallback apply;
  _Op(this.cmd, this.apply);
}

/// Satu objek per mesin: koneksi BLE + draft setting (profile) + logika sinkronisasi.
class MachineLink extends ChangeNotifier {
  MachineLink(this.profile, this.onPersist);
  final MachineProfile profile;
  final void Function() onPersist;

  LinkPhase phase = LinkPhase.idle;
  String? lastError;
  MachineStatus? status;
  String fwVersion = '', devType = '';
  bool configLoaded = false, pendingDecision = false, syncing = false;

  // konfigurasi yang SEDANG ada di ESP32 (dibaca lewat GET)
  final Map<String, String> devParams = {};
  final List<ProgramCfg> devPrograms = List<ProgramCfg>.of(kDefaultPrograms);
  List<int> devRing = List<int>.of(kDefaultRing);
  String devName = '';

  final StreamController<String> events = StreamController<String>.broadcast();

  BluetoothDevice? _dev;
  BluetoothCharacteristic? _rx;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final List<_Pending> _queue = [];
  _Pending? _waiting;
  bool _busy = false, _firstLoad = true;
  final List<int> _ohmHist = [];

  // ---------------- getter ----------------
  bool get isReady => phase == LinkPhase.ready;
  bool get devRemoteStart => devParams['remote_start'] == '1';
  bool get devDoorResume => devParams['door_resume'] != '0';
  double? get avgOhm => _ohmHist.length < 5 ? null : _ohmHist.reduce((a, b) => a + b) / _ohmHist.length;

  bool get draftEqualsDevice {
    for (final m in kParamMeta) {
      if (kDeviceOwned.contains(m.key)) continue;
      if (!sameNum(profile.params[m.key], devParams[m.key])) return false;
    }
    for (int i = 0; i < 9; i++) {
      if (!profile.programs[i].same(devPrograms[i])) return false;
    }
    return listEquals(profile.ring, devRing) && profile.name == devName;
  }

  /// Ada perubahan draft yang belum ada di ESP32.
  bool get needsSync => isReady && configLoaded ? !draftEqualsDevice : profile.dirty;

  // ---------------- koneksi ----------------
  Future<void> connect() async {
    final id = profile.deviceId;
    if (id == null) {
      lastError = 'ESP belum dipasangkan';
      notifyListeners();
      return;
    }
    if (phase != LinkPhase.idle) return;
    lastError = null;
    phase = LinkPhase.connecting;
    notifyListeners();
    final d = BluetoothDevice.fromId(id);
    try {
      final st = await FlutterBluePlus.adapterState.first;
      if (st != BluetoothAdapterState.on) throw 'Bluetooth belum aktif';
      await d.connect(timeout: const Duration(seconds: 12));
      _dev = d;
      _connSub = d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _cleanup();
      });
      if (Platform.isAndroid) await d.requestMtu(185); // WAJIB: baris dari ESP > 20 byte
      final svcs = await d.discoverServices();
      final svc = svcs.firstWhere((s) => s.uuid == kSvc);
      BluetoothCharacteristic? tx;
      for (final c in svc.characteristics) {
        if (c.uuid == kRx) _rx = c;
        if (c.uuid == kTx) tx = c;
      }
      if (_rx == null || tx == null) throw 'karakteristik BLE tidak lengkap';
      await tx.setNotifyValue(true);
      _notifySub = tx.onValueReceived.listen(_onData);

      phase = LinkPhase.authing;
      notifyListeners();
      final r = await send('AUTH ${profile.pin}');
      if (!r.ok) {
        lastError = r.info == 'locked' ? 'Terkunci 60 detik (PIN salah berulang)' : 'PIN salah';
        await disconnect();
        return;
      }
      phase = LinkPhase.ready;
      notifyListeners();
      send('GET', expectReply: false); // balasan: V, C..., P..., N, R (R = penutup), S
    } catch (e) {
      lastError = 'Gagal terhubung: $e';
      try {
        await d.disconnect();
      } catch (_) {}
      _cleanup();
    }
  }

  Future<void> bind(String deviceId, String pin) async {
    profile.deviceId = deviceId;
    profile.pin = pin;
    onPersist();
    notifyListeners();
    await connect();
  }

  Future<void> disconnect() async {
    try {
      await _dev?.disconnect();
    } catch (_) {}
    _cleanup();
  }

  void _cleanup() {
    _notifySub?.cancel();
    _connSub?.cancel();
    _notifySub = null;
    _connSub = null;
    _rx = null;
    _dev = null;
    for (final p in _queue) {
      if (!p.c.isCompleted) p.c.complete(const Reply(false, 'terputus'));
    }
    _queue.clear();
    final w = _waiting;
    if (w != null && !w.c.isCompleted) w.c.complete(const Reply(false, 'terputus'));
    phase = LinkPhase.idle;
    status = null;
    configLoaded = false;
    pendingDecision = false;
    syncing = false;
    _firstLoad = true;
    _ohmHist.clear();
    notifyListeners();
  }

  // ---------------- kirim perintah (serial, satu per satu) ----------------
  Future<Reply> send(String cmd, {bool expectReply = true}) {
    final p = _Pending(cmd, expectReply);
    _queue.add(p);
    _pump();
    return p.c.future;
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    while (_queue.isNotEmpty) {
      final p = _queue.removeAt(0);
      if (_rx == null) {
        p.c.complete(const Reply(false, 'terputus'));
        continue;
      }
      _waiting = p;
      try {
        await _rx!.write(utf8.encode(p.cmd));
      } catch (e) {
        if (!p.c.isCompleted) p.c.complete(Reply(false, '$e'));
        _waiting = null;
        continue;
      }
      if (!p.expectReply) {
        if (!p.c.isCompleted) p.c.complete(const Reply(true, ''));
        _waiting = null;
        continue;
      }
      try {
        await p.c.future.timeout(const Duration(seconds: 4));
      } on TimeoutException {
        if (!p.c.isCompleted) p.c.complete(const Reply(false, 'timeout'));
      }
      _waiting = null;
    }
    _busy = false;
  }

  void _reply(bool ok, String name, String info) {
    final w = _waiting;
    if (w != null && w.name == name && !w.c.isCompleted) w.c.complete(Reply(ok, info));
  }

  // ---------------- terima notifikasi ----------------
  void _onData(List<int> v) {
    final line = utf8.decode(v, allowMalformed: true).trim();
    if (line.isEmpty) return;
    final f = line.split(',');
    switch (f[0]) {
      case 'S':
        final s = MachineStatus.parse(f);
        if (s != null) {
          status = s;
          if (s.sensorOk && s.ohm > 0) {
            _ohmHist.add(s.ohm);
            if (_ohmHist.length > 10) _ohmHist.removeAt(0);
          }
        }
        break;
      case 'C':
        if (f.length >= 3) devParams[f[1]] = f[2];
        break;
      case 'P':
        // Nama program bisa mengandung koma ("2,5 JAM"), jadi 6 angka dibaca dari belakang.
        if (f.length >= 9) {
          final idx = int.tryParse(f[1]) ?? 0;
          if (idx >= 1 && idx <= 9) {
            final n = f.length;
            int v6(int k) => int.tryParse(f[n - 6 + k]) ?? 0;
            devPrograms[idx - 1] = ProgramCfg(
                name: f.sublist(2, n - 6).join(','),
                minutes: v6(0), heat: v6(1), onS: v6(2), offS: v6(3), tCut: v6(4), coolS: v6(5));
          }
        }
        break;
      case 'V':
        if (f.length >= 2) fwVersion = f[1];
        if (f.length >= 3) devType = f[2].toLowerCase();
        break;
      case 'N':
        devName = f.sublist(1).join(',');
        break;
      case 'R':
        if (f.length >= 10) {
          devRing = [for (int k = 1; k <= 9; k++) int.tryParse(f[k]) ?? 1];
          _onConfigLoaded();
        }
        break;
      case 'E':
        events.add(line);
        break;
      case 'OK':
        _reply(true, f.length > 1 ? f[1] : '', '');
        break;
      case 'ERR':
        _reply(false, f.length > 1 ? f[1] : '', f.length > 2 ? f[2] : 'error');
        break;
    }
    notifyListeners();
  }

  void _onConfigLoaded() {
    configLoaded = true;
    for (final k in ['ntc_off', 'ntc_beta']) {
      final v = devParams[k];
      if (v != null) profile.params[k] = v; // kalibrasi selalu mengikuti ESP
    }
    if (_firstLoad) {
      _firstLoad = false;
      if (profile.fresh) {
        profile.fresh = false;
        _pull(keepName: true);
        if (profile.name != devName) sync();
      } else if (!profile.dirty) {
        _pull();
      } else if (draftEqualsDevice) {
        profile.dirty = false;
      } else {
        pendingDecision = true;
      }
    }
    onPersist();
  }

  void _pull({bool keepName = false}) {
    for (final e in devParams.entries) {
      profile.params[e.key] = e.value;
    }
    profile.programs = List<ProgramCfg>.of(devPrograms);
    profile.ring = List<int>.of(devRing);
    if (!keepName && devName.isNotEmpty) profile.name = devName;
    profile.dirty = false;
  }

  // ---------------- edit draft (boleh offline) ----------------
  void _touch() {
    profile.dirty = true;
    onPersist();
    notifyListeners();
  }

  String? editParam(String key, String value) {
    final meta = kParamMeta.firstWhere((m) => m.key == key);
    final v = double.tryParse(value.replaceAll(',', '.'));
    if (v == null || v < meta.min || v > meta.max) return 'Nilai harus ${fmtNum(meta.min)}-${fmtNum(meta.max)}';
    final test = Map<String, String>.of(profile.params);
    test[key] = (meta.isInt || meta.isBool) ? v.round().toString() : v.toString();
    final err = checkDraft(test, profile.programs);
    if (err != null) return err;
    profile.params = test;
    _touch();
    return null;
  }

  String? editProgram(int i, ProgramCfg p) {
    final list = List<ProgramCfg>.of(profile.programs);
    list[i] = p;
    final err = checkDraft(profile.params, list);
    if (err != null) return err;
    profile.programs = list;
    _touch();
    return null;
  }

  void editRing(List<int> ring) {
    profile.ring = List<int>.of(ring);
    _touch();
  }

  String? rename(String raw) {
    final err = nameError(raw);
    if (err != null) return err;
    profile.name = normName(raw);
    _touch();
    return null;
  }

  /// Draft kembali ke nilai awal (kalibrasi tetap). Baru berlaku di mesin setelah SYNC.
  void resetDraft() {
    profile.params = Map<String, String>.of(kDefaultParams)
      ..['ntc_off'] = profile.params['ntc_off'] ?? '0.00'
      ..['ntc_beta'] = profile.params['ntc_beta'] ?? '3950.00';
    profile.programs = List<ProgramCfg>.of(kDefaultPrograms);
    profile.ring = List<int>.of(kDefaultRing);
    _touch();
  }

  // ---------------- sinkronisasi ----------------
  /// Kirim draft ke ESP32 lalu SAVE (permanen di flash). Null = sukses, selain itu pesan error.
  Future<String?> sync() async {
    if (!isReady || !configLoaded) return 'Mesin belum terhubung';
    if (!(status?.canEdit ?? false)) return 'Mesin sedang berjalan - hentikan dulu';
    final bad = checkDraft(profile.params, profile.programs);
    if (bad != null) return bad;
    syncing = true;
    notifyListeners();

    final ops = <_Op>[];
    for (final meta in kParamMeta) {
      if (kDeviceOwned.contains(meta.key)) continue;
      final want = profile.params[meta.key] ?? kDefaultParams[meta.key] ?? '0';
      if (!sameNum(want, devParams[meta.key])) {
        final val = double.tryParse(want) ?? 0;
        final w = (meta.isInt || meta.isBool) ? val.round().toString() : val.toString();
        ops.add(_Op('SET ${meta.key} $w', () => devParams[meta.key] = want));
      }
    }
    for (int i = 0; i < 9; i++) {
      final p = profile.programs[i];
      if (!p.same(devPrograms[i])) {
        ops.add(_Op('PSET ${i + 1} ${p.minutes} ${p.heat} ${p.onS} ${p.offS} ${p.tCut} ${p.coolS}', () => devPrograms[i] = p));
      }
    }
    if (!listEquals(profile.ring, devRing)) {
      final r = List<int>.of(profile.ring);
      ops.add(_Op('RING ${r.join(' ')}', () => devRing = r));
    }
    if (profile.name != devName) {
      final nm = profile.name;
      ops.add(_Op('NAME $nm', () => devName = nm));
    }

    // Dua putaran: item yang ditolak 'constraint' (urutan t_hard vs tCut) dicoba lagi setelah yang lain masuk.
    var pending = ops;
    String lastErr = '';
    for (int pass = 0; pass < 2 && pending.isNotEmpty; pass++) {
      final next = <_Op>[];
      for (final op in pending) {
        final r = await send(op.cmd);
        if (r.ok) {
          op.apply();
        } else {
          next.add(op);
          lastErr = r.info;
        }
      }
      pending = next;
    }
    if (pending.isNotEmpty) {
      syncing = false;
      notifyListeners();
      return 'Gagal mengirim ${pending.length} item: ${errText(lastErr)}';
    }
    if (ops.isNotEmpty || (status?.dirty ?? false)) {
      final sv = await send('SAVE');
      if (!sv.ok) {
        syncing = false;
        notifyListeners();
        return 'Gagal menyimpan permanen di mesin: ${errText(sv.info)}';
      }
    }
    profile.dirty = false;
    onPersist();
    syncing = false;
    send('GET', expectReply: false);
    notifyListeners();
    return null;
  }

  Future<String?> resolveSend() {
    pendingDecision = false;
    notifyListeners();
    return sync();
  }

  void resolvePull() {
    _pull();
    pendingDecision = false;
    onPersist();
    notifyListeners();
  }

  /// Buang draft, ambil apa adanya dari ESP32 (dev* selalu mutakhir). Hanya saat terhubung.
  void pullFromDevice() {
    if (!isReady || !configLoaded) return;
    _pull();
    onPersist();
    notifyListeners();
  }

  // ---------------- perintah langsung (butuh terhubung) ----------------
  Future<Reply> selectProgram(int n) => send('SEL $n');
  Future<Reply> startRun() => send('START');
  Future<Reply> pause() => send('PAUSE');
  Future<Reply> resume() => send('RESUME');
  Future<Reply> stop() => send('STOP');
  Future<Reply> emergency() => send('EMERG');

  /// Dipakai kalibrasi beta (milik perangkat, langsung ke ESP32, tidak lewat draft).
  Future<Reply> setDeviceParam(String key, String value) async {
    final r = await send('SET $key $value');
    if (r.ok) {
      devParams[key] = value;
      profile.params[key] = value;
      onPersist();
      notifyListeners();
    }
    return r;
  }

  Future<Reply> calRef(double refC) async {
    final r = await send('CALREF ${refC.toStringAsFixed(1)}');
    if (r.ok) send('GET', expectReply: false);
    return r;
  }

  Future<Reply> saveDevice() => send('SAVE');

  Future<String?> changePin(String pin) async {
    final r = await send('SET pin $pin');
    if (!r.ok) return errText(r.info);
    final sv = await send('SAVE');
    if (!sv.ok) return 'PIN diubah tapi gagal disimpan: ${errText(sv.info)}';
    profile.pin = pin;
    onPersist();
    notifyListeners();
    return null;
  }
}
