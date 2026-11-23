import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'models.dart';
import 'profile.dart';
import 'schema.dart';
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

/// Satu objek per mesin (dryer atau mesin cuci): koneksi BLE + draft setting (profile) + sinkronisasi.
class MachineLink extends ChangeNotifier {
  MachineLink(this.profile, this.onPersist);
  final MachineProfile profile;
  final void Function() onPersist;
  late final MachineSchema schema = schemaOf(profile.type);

  LinkPhase phase = LinkPhase.idle;
  String? lastError;
  MachineStatus? status;      // dryer
  WasherStatus? wstatus;      // mesin cuci
  MotorInfo? motor;           // mesin cuci
  String fwVersion = '', devType = '';
  bool configLoaded = false, pendingDecision = false, syncing = false;
  bool orderOk = false;
  String orderCode = '', runProg = '';

  // konfigurasi yang SEDANG ada di ESP32 (dibaca lewat GET)
  final Map<String, String> devParams = {};
  late final List<ProgramCfg> devPrograms = schema.defaultPrograms();
  late List<int> devRing = List<int>.of(schema.defRing);
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
  bool get isDryer => profile.type == 'dryer';
  bool get hasStatus => isDryer ? status != null : wstatus != null;
  bool get canEdit => isDryer ? (status?.canEdit ?? false) : (wstatus?.canEdit ?? false);
  bool get running => isDryer ? (status?.running ?? false) : (wstatus?.running ?? false);
  int get stateCode => isDryer ? (status?.state ?? 0) : (wstatus?.state ?? 0);
  int get remainS => isDryer ? (status?.remainS ?? 0) : (wstatus?.remainS ?? 0);
  int get totalS => isDryer ? (status?.totalS ?? 0) : (wstatus?.totalS ?? 0);
  int get progId => isDryer ? (status?.prog ?? 0) : (wstatus?.prog ?? 0);
  bool get devDirty => isDryer ? (status?.dirty ?? false) : (wstatus?.dirty ?? false);
  bool get devRemoteStart => devParams['remote_start'] == '1';
  bool get devDoorResume => devParams['door_resume'] != '0';
  bool get devOrderReq => devParams['order_req'] == '1';
  double? get avgOhm => _ohmHist.length < 5 ? null : _ohmHist.reduce((a, b) => a + b) / _ohmHist.length;

  bool get draftEqualsDevice {
    for (final m in schema.params) {
      if (schema.deviceOwned.contains(m.key)) continue;
      if (!sameNum(profile.params[m.key], devParams[m.key])) return false;
    }
    for (int i = 0; i < schema.n; i++) {
      if (!profile.programs[i].same(devPrograms[i])) return false;
    }
    return listEquals(profile.ring, devRing) && profile.name == devName;
  }

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
      send('GET', expectReply: false);
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
    wstatus = null;
    motor = null;
    configLoaded = false;
    pendingDecision = false;
    syncing = false;
    orderOk = false;
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
        final prevState = stateCode;
        if (isDryer) {
          final s = MachineStatus.parse(f);
          if (s != null) {
            status = s;
            if (s.sensorOk && s.ohm > 0) {
              _ohmHist.add(s.ohm);
              if (_ohmHist.length > 10) _ohmHist.removeAt(0);
            }
            if (s.state == 2 && s.prog >= 1 && s.prog <= schema.n) runProg = schema.progNames[s.prog - 1];
          }
        } else {
          final s = WasherStatus.parse(f);
          if (s != null) {
            wstatus = s;
            if (s.state == 2 && s.prog >= 1 && s.prog <= schema.n) runProg = schema.progNames[s.prog - 1];
          }
        }
        // mesin baru mulai (dari layar pilihan ke jalan) dengan order yang di-scan -> kabari store (update status Firestore)
        if (prevState == 1 && stateCode == 2 && orderOk && orderCode.isNotEmpty) events.add('E,STARTED,$orderCode');
        break;
      case 'M':
        motor = MotorInfo.parse(f);
        break;
      case 'O':
        orderOk = f.length > 1 && f[1] == '1';
        orderCode = f.length > 2 ? f.sublist(2).join(',') : '';
        break;
      case 'C':
        if (f.length >= 3) devParams[f[1]] = f[2];
        break;
      case 'P':
        // Nama program bisa mengandung koma ("2,5 JAM"): angka dibaca dari belakang.
        final nf = schema.fields.length;
        if (f.length >= 3 + nf) {
          final idx = int.tryParse(f[1]) ?? 0;
          if (idx >= 1 && idx <= schema.n) {
            final n = f.length;
            devPrograms[idx - 1] = ProgramCfg(f.sublist(2, n - nf).join(','), [for (int k = 0; k < nf; k++) int.tryParse(f[n - nf + k]) ?? 0]);
          }
        }
        break;
      case 'V':
        if (f.length >= 2) fwVersion = f[1];
        if (f.length >= 3) {
          devType = f[2].toLowerCase();
          if (devType != profile.type) {
            lastError = 'ESP ini bertipe "$devType", bukan ${schema.title.toLowerCase()}';
            disconnect();
            return;
          }
        }
        break;
      case 'N':
        devName = f.sublist(1).join(',');
        break;
      case 'R':
        if (f.length >= 1 + schema.n) {
          devRing = [for (int k = 1; k <= schema.n; k++) int.tryParse(f[k]) ?? 1];
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
    for (final k in schema.deviceOwned) {
      final v = devParams[k];
      if (v != null) profile.params[k] = v; // kalibrasi / hasil belajar selalu mengikuti ESP
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
    final meta = schema.meta(key);
    if (meta == null) return 'Parameter tidak dikenal';
    final v = double.tryParse(value.replaceAll(',', '.'));
    if (v == null || v < meta.min || v > meta.max) return 'Nilai harus ${fmtNum(meta.min)}-${fmtNum(meta.max)}';
    final test = Map<String, String>.of(profile.params);
    test[key] = (meta.isInt || meta.isBool) ? v.round().toString() : v.toString();
    final err = schema.check(test, profile.programs);
    if (err != null) return err;
    profile.params = test;
    _touch();
    return null;
  }

  String? resetParam(String key) => editParam(key, schema.defParams[key] ?? '0');

  String? editProgram(int i, ProgramCfg p) {
    final list = List<ProgramCfg>.of(profile.programs);
    list[i] = p;
    final err = schema.check(profile.params, list);
    if (err != null) return err;
    profile.programs = list;
    _touch();
    return null;
  }

  String? resetProgram(int i) => editProgram(i, ProgramCfg(schema.progNames[i], List<int>.of(schema.defProgs[i])));

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

  /// Draft kembali ke nilai awal firmware (kalibrasi / hasil belajar motor tetap). Berlaku di mesin setelah SYNC.
  void resetDraft() {
    final keep = <String, String>{for (final k in schema.deviceOwned) if (profile.params[k] != null) k: profile.params[k]!};
    profile.params = Map<String, String>.of(schema.defParams)..addAll(keep);
    profile.programs = schema.defaultPrograms();
    profile.ring = List<int>.of(schema.defRing);
    _touch();
  }

  // ---------------- sinkronisasi ----------------
  Future<String?> sync() async {
    if (!isReady || !configLoaded) return 'Mesin belum terhubung';
    if (!canEdit) return 'Mesin sedang berjalan - hentikan dulu';
    final bad = schema.check(profile.params, profile.programs);
    if (bad != null) return bad;
    syncing = true;
    notifyListeners();

    final ops = <_Op>[];
    for (final meta in schema.params) {
      if (schema.deviceOwned.contains(meta.key)) continue;
      final want = profile.params[meta.key] ?? schema.defParams[meta.key] ?? '0';
      if (!sameNum(want, devParams[meta.key])) {
        final val = double.tryParse(want) ?? 0;
        final w = (meta.isInt || meta.isBool) ? val.round().toString() : val.toString();
        ops.add(_Op('SET ${meta.key} $w', () => devParams[meta.key] = want));
      }
    }
    for (int i = 0; i < schema.n; i++) {
      final p = profile.programs[i];
      if (!p.same(devPrograms[i])) ops.add(_Op('PSET ${i + 1} ${p.v.join(' ')}', () => devPrograms[i] = p));
    }
    if (!listEquals(profile.ring, devRing)) {
      final r = List<int>.of(profile.ring);
      ops.add(_Op('RING ${r.join(' ')}', () => devRing = r));
    }
    if (profile.name != devName) {
      final nm = profile.name;
      ops.add(_Op('NAME $nm', () => devName = nm));
    }

    // Dua putaran: item yang ditolak 'constraint' (saling bergantung) dicoba lagi setelah yang lain masuk.
    var pending = ops;
    String lastErr = '';
    for (int pass = 0; pass < 3 && pending.isNotEmpty; pass++) {
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
    if (ops.isNotEmpty || devDirty) {
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

  /// Barcode order: dikirim ke mesin. Jika order_req aktif, mesin baru bisa mulai setelah ini.
  Future<Reply> sendOrder(String code, [String text = '']) => send(text.isEmpty ? 'ORDER $code' : 'ORDER $code $text');
  Future<Reply> clearOrder() => send('ORDERCLR');

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
  Future<Reply> learnMotor() => send('MLEARN');
  Future<Reply> testMotor(int dir, int rpm, int sec) => send('MTEST $dir $rpm $sec');
  Future<Reply> testSoap(int sec) => send('SOAP $sec');

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
