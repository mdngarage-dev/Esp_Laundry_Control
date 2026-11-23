import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'history.dart';
import 'machine_link.dart';
import 'order_service.dart';
import 'profile.dart';
import 'ui_helpers.dart';

/// Daftar semua mesin (disimpan di HP) + scan BLE untuk menambah/memasangkan ESP32.
class MachineStore extends ChangeNotifier {
  final List<MachineLink> machines = [];
  List<ScanResult> scanResults = [];
  bool scanning = false;
  String? scanError;
  StreamSubscription<List<ScanResult>>? _scanSub;

  Set<String> get boundIds => {for (final m in machines) if (m.profile.deviceId != null) m.profile.deviceId!};
  List<MachineLink> byType(String t) => machines.where((m) => m.profile.type == t).toList();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('machines_v3');
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List) {
          machines.add(_make(MachineProfile.fromJson(Map<String, dynamic>.from(e as Map))));
        }
      } catch (_) {
        // data rusak: mulai kosong
      }
    }
    notifyListeners();
  }

  Future<void> persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('machines_v3', jsonEncode(machines.map((m) => m.profile.toJson()).toList()));
  }

  MachineLink _make(MachineProfile p) {
    final l = MachineLink(p, persist);
    l.addListener(notifyListeners);
    l.events.stream.listen((e) => _onEvent(l, e));
    return l;
  }

  void _onEvent(MachineLink l, String e) {
    final f = e.split(',');
    if (f.length < 2) return;
    final n = l.profile.name;
    String? msg;
    switch (f[1]) {
      case 'DONE':
        final order = f.length > 2 ? f.sublist(2).join(',') : '';
        msg = '$n: selesai${order.isEmpty ? '' : ' (order $order)'}';
        orderLog.add(OrderEntry(order, n, l.runProg, DateTime.now()));
        break;
      case 'STARTED':
        final code = f.length > 2 ? f[2] : '';
        if (code.isNotEmpty && orders.writeStatus) {
          orders.markProcessing(code).then((m) => messengerKey.currentState?.showSnackBar(SnackBar(content: Text('$n: $m'), duration: const Duration(seconds: 6))));
        }
        break;
      case 'ORDER_REQUIRED':
        msg = '$n: scan barcode order dulu sebelum mulai';
        break;
      case 'ORDER_EXPIRED':
        msg = '$n: hasil scan barcode kedaluwarsa, scan ulang';
        break;
      case 'WARN':
        msg = '$n: beban tidak seimbang, peras dengan putaran rendah';
        break;
      case 'LOCK_LOST':
        msg = '$n: kunci pintu terlepas, proses dijeda';
        break;
      case 'DOOR_OPEN':
        msg = '$n: pintu terbuka, proses dijeda';
        break;
      case 'FAULT':
        final c = f.length > 2 ? int.tryParse(f[2]) ?? 0 : 0;
        msg = '$n: ERROR E$c - ${l.isDryer ? faultText(c) : washerFaultText(c)}';
        break;
    }
    if (msg != null) {
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 8)));
    }
  }

  MachineLink addOffline(String type, String name) {
    final l = _make(MachineProfile.create(type, name));
    machines.add(l);
    persist();
    notifyListeners();
    return l;
  }

  MachineLink addDemo(String type, String name) {
    final l = _make(MachineProfile.create(type, name, deviceId: 'DEMO', fresh: true));
    machines.add(l);
    persist();
    notifyListeners();
    l.connect();
    return l;
  }

  /// Tambah mesin sekaligus pasangkan ke ESP32. Null = sukses.
  Future<String?> addAndBind(String type, String name, BluetoothDevice d, String pin) async {
    await stopScan();
    final l = _make(MachineProfile.create(type, name, deviceId: d.remoteId.str, pin: pin, fresh: true));
    await l.connect();
    if (!l.isReady) {
      final err = l.lastError ?? 'Gagal terhubung';
      l.removeListener(notifyListeners);
      return err;
    }
    machines.add(l);
    await persist();
    notifyListeners();
    return null;
  }

  Future<String?> bindExisting(MachineLink l, BluetoothDevice d, String pin) async {
    await stopScan();
    await l.bind(d.remoteId.str, pin);
    return l.isReady ? null : (l.lastError ?? 'Gagal terhubung');
  }

  Future<void> remove(MachineLink l) async {
    await l.disconnect();
    l.removeListener(notifyListeners);
    machines.remove(l);
    await persist();
    notifyListeners();
  }

  /// Hubungkan satu per satu (lebih stabil di Android daripada serentak).
  Future<void> connectAll() async {
    for (final m in List<MachineLink>.of(machines)) {
      if (m.profile.deviceId != null && m.phase == LinkPhase.idle) await m.connect();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<void> scan() async {
    scanError = null;
    scanResults = [];
    scanning = true;
    notifyListeners();
    try {
      final st = await FlutterBluePlus.adapterState.first;
      if (st != BluetoothAdapterState.on) {
        scanError = 'Bluetooth belum aktif';
        scanning = false;
        notifyListeners();
        return;
      }
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((r) {
        scanResults = r.where((x) => !boundIds.contains(x.device.remoteId.str)).toList();
        notifyListeners();
      });
      await FlutterBluePlus.startScan(withServices: [kSvc], timeout: const Duration(seconds: 8));
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
    } catch (e) {
      scanError = 'Scan gagal: $e';
    }
    scanning = false;
    notifyListeners();
  }
}

final MachineStore store = MachineStore();
