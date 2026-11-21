import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

final Guid kSvc = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
final Guid kRx = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e'); // app menulis ke sini
final Guid kTx = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e'); // ESP32 notify ke sini

enum LinkPhase { idle, scanning, connecting, authing, ready }

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

/// Satu-satunya objek yang bicara BLE ke mesin. Dipakai semua halaman lewat variabel global [link].
class DryerLink extends ChangeNotifier {
  LinkPhase phase = LinkPhase.idle;
  String? lastError;
  MachineStatus? status;
  String fwVersion = '';
  bool configLoaded = false;
  List<ScanResult> results = [];
  final Map<String, String> params = {};
  final List<ProgramCfg> programs = List.generate(
      9, (i) => ProgramCfg(name: kDefaultNames[i], minutes: 0, heat: 0, onS: 0, offS: 0, tCut: 0, coolS: 0));
  final StreamController<String> events = StreamController<String>.broadcast();
  String pin = '';

  BluetoothDevice? _dev;
  BluetoothCharacteristic? _rx;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  final List<_Pending> _queue = [];
  _Pending? _waiting;
  bool _busy = false;
  final List<int> _ohmHist = [];

  bool get remoteStartOn => params['remote_start'] == '1';
  bool get doorResumeOn => params['door_resume'] != '0';
  double pNum(String k, double def) => double.tryParse(params[k] ?? '') ?? def;

  /// Rata-rata ~10 pembacaan resistansi NTC terakhir (null kalau belum cukup).
  double? get avgOhm {
    if (_ohmHist.length < 5) return null;
    return _ohmHist.reduce((a, b) => a + b) / _ohmHist.length;
  }

  // ---------------- scan & connect ----------------
  Future<void> startScan() async {
    lastError = null;
    results = [];
    try {
      final st = await FlutterBluePlus.adapterState.first;
      if (st != BluetoothAdapterState.on) {
        lastError = 'Bluetooth belum aktif';
        notifyListeners();
        return;
      }
      phase = LinkPhase.scanning;
      notifyListeners();
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((r) {
        results = r;
        notifyListeners();
      });
      await FlutterBluePlus.startScan(withServices: [kSvc], timeout: const Duration(seconds: 8));
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
    } catch (e) {
      lastError = 'Scan gagal: $e';
    }
    if (phase == LinkPhase.scanning) phase = LinkPhase.idle;
    notifyListeners();
  }

  Future<void> autoConnect() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString('last_id');
    final pn = p.getString('pin');
    if (id == null || pn == null) return;
    await connect(BluetoothDevice.fromId(id), pn);
  }

  Future<void> connect(BluetoothDevice d, String pinText) async {
    pin = pinText;
    lastError = null;
    phase = LinkPhase.connecting;
    notifyListeners();
    try {
      await FlutterBluePlus.stopScan();
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
      final r = await send('AUTH $pin');
      if (!r.ok) {
        lastError = errText2(r.info);
        await disconnect();
        return;
      }
      final p = await SharedPreferences.getInstance();
      await p.setString('pin', pin);
      await p.setString('last_id', d.remoteId.str);
      phase = LinkPhase.ready;
      notifyListeners();
      send('GET', expectReply: false); // balasan: V, C..., P..., S
    } catch (e) {
      lastError = 'Gagal terhubung: $e';
      try {
        await d.disconnect();
      } catch (_) {}
      _cleanup();
    }
  }

  String errText2(String code) => code == 'pin' ? 'PIN salah' : code == 'locked' ? 'Terkunci 60 detik (PIN salah berulang)' : code;

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
        if (f.length >= 3) params[f[1]] = f[2];
        break;
      case 'P':
        // Nama program bisa mengandung koma ("2,5 JAM"), jadi 6 angka dibaca dari belakang.
        if (f.length >= 9) {
          final idx = int.tryParse(f[1]) ?? 0;
          if (idx >= 1 && idx <= 9) {
            final n = f.length;
            int v6(int k) => int.tryParse(f[n - 6 + k]) ?? 0;
            programs[idx - 1] = ProgramCfg(
                name: f.sublist(2, n - 6).join(','),
                minutes: v6(0), heat: v6(1), onS: v6(2), offS: v6(3), tCut: v6(4), coolS: v6(5));
            if (idx == 9) configLoaded = true;
          }
        }
        break;
      case 'V':
        if (f.length >= 2) fwVersion = f[1];
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

  // ---------------- perintah tingkat tinggi ----------------
  Future<Reply> selectProgram(int n) => send('SEL $n');
  Future<Reply> startRun() => send('START');
  Future<Reply> pause() => send('PAUSE');
  Future<Reply> resume() => send('RESUME');
  Future<Reply> stop() => send('STOP');
  Future<Reply> emergency() => send('EMERG');

  Future<Reply> setParam(String key, String value) async {
    final r = await send('SET $key $value');
    if (r.ok) {
      params[key] = value;
      notifyListeners();
    }
    return r;
  }

  Future<Reply> setProgram(int index, ProgramCfg p) async {
    final r = await send('PSET ${index + 1} ${p.minutes} ${p.heat} ${p.onS} ${p.offS} ${p.tCut} ${p.coolS}');
    if (r.ok) {
      programs[index] = p;
      notifyListeners();
    }
    return r;
  }

  Future<Reply> calRef(double refC) async {
    final r = await send('CALREF ${refC.toStringAsFixed(1)}');
    if (r.ok) send('GET', expectReply: false); // segarkan ntc_off
    return r;
  }

  Future<Reply> save() => send('SAVE');

  Future<Reply> reloadFromFlash() async {
    final r = await send('LOAD');
    if (r.ok) send('GET', expectReply: false);
    return r;
  }

  Future<Reply> factoryDefaults() async {
    final r = await send('DEFAULTS');
    if (r.ok) send('GET', expectReply: false);
    return r;
  }
}

final DryerLink link = DryerLink();
