import 'dart:async';
import 'dart:math' as math;

import 'models.dart';
import 'schema.dart';

class _Snap {
  _Snap(this.params, this.progs, this.ring, this.name);
  final Map<String, String> params;
  final List<List<int>> progs;
  final List<int> ring;
  final String name;
}

class _Win {
  _Win(this.type, this.start, this.end);
  final String type;
  final double start, end;
}

/// Mesin palsu di dalam aplikasi: menerima perintah teks yang sama dengan firmware (SEL, START, SET, PSET, SYNC, ORDER, ...)
/// dan mengirim baris status (S, M, O, C, P, ...) seperti ESP32 asli. Hanya untuk uji tampilan dan alur, BUKAN uji perangkat keras.
class DemoDevice {
  DemoDevice(this.type, this.emit) : schema = schemaOf(type) {
    params = Map<String, String>.of(schema.defParams);
    progs = [for (final p in schema.defProgs) List<int>.of(p)];
    ring = List<int>.of(schema.defRing);
    name = type == 'dryer' ? 'Dryer' : 'Washer';
    _saved = _snap();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  final String type;
  final void Function(String) emit;
  final MachineSchema schema;
  bool get dryer => type == 'dryer';

  late Map<String, String> params;
  late List<List<int>> progs;
  late List<int> ring;
  late String name;
  late _Snap _saved;
  Timer? _timer;

  /// Detik simulasi per detik nyata (1 = waktu asli). Bisa diubah dari panel demo.
  int speed = 20;

  String pin = '123456';
  int st = 0, prog = 0, fault = 0, total = 0, doneLeft = 0, stopLeft = 0, testLeft = 0, closedTicks = 0, pausedTicks = 0, unbalTries = 0;
  double elapsed = 0, temp = 28, rpm = 0, rpmTarget = 0, edges = 0;
  bool dirty = false, doorOpen = false, orderOk = false;
  bool gas = false, ign = false, fillOn = false, drainOn = false, soapOn = false, levelFull = false, lockRelay = false;
  int heat = 0, stage = 0, testKind = 0; // testKind: 1 learn, 2 mtest, 3 soap
  double spinCap = 100000;
  String orderCode = '';
  List<_Win> wins = [];

  void stop() => _timer?.cancel();

  // ---------------- panel demo ----------------
  void setDoorOpen(bool v) => doorOpen = v;
  void injectFault(int code) {
    _off();
    st = 7;
    fault = code;
    emit('E,FAULT,$code');
  }

  void injectUnbal() {
    unbalTries = 3;
    spinCap = 300;
    emit('E,WARN,UNBAL');
  }

  void skipToEnd() {
    if (st == 2) elapsed = math.max(0, total - 6.0);
  }

  // ---------------- util ----------------
  double _pn(String k) => double.tryParse(params[k] ?? '') ?? 0;
  bool get _learned => params['mot_ok'] == '1';
  _Snap _snap() => _Snap(Map<String, String>.of(params), [for (final p in progs) List<int>.of(p)], List<int>.of(ring), name);
  void _restore(_Snap s) {
    params = Map<String, String>.of(s.params);
    progs = [for (final p in s.progs) List<int>.of(p)];
    ring = List<int>.of(s.ring);
    name = s.name;
  }

  String? _check() => schema.check(params, [for (int i = 0; i < schema.n; i++) ProgramCfg(schema.progNames[i], progs[i])]);

  void _off() {
    st = 0;
    fault = 0;
    elapsed = 0;
    total = 0;
    gas = ign = fillOn = drainOn = soapOn = levelFull = lockRelay = false;
    heat = 0;
    stage = 0;
    rpmTarget = 0;
    orderOk = false;
    testKind = 0;
  }

  // ---------------- perintah dari aplikasi ----------------
  void handle(String line) {
    final tok = line.trim().split(RegExp(r'[ ,]+'));
    if (tok.isEmpty || tok[0].isEmpty) return;
    final cmd = tok[0].toUpperCase();
    final a = tok.sublist(1);
    void ok() => emit('OK,$cmd');
    void err(String why) => emit('ERR,$cmd,$why');
    final idle = st == 0 || st == 1 || st == 6 || st == 7;
    final nf = schema.fields.length;

    if (cmd == 'AUTH') {
      if (a.isNotEmpty && a[0] == pin) {
        ok();
      } else {
        err('pin');
      }
      return;
    }
    if (cmd == 'GET') {
      _dump();
      return;
    }
    if (cmd == 'EMERG') {
      _off();
      ok();
      return;
    }
    if (cmd == 'STOP') {
      if (st >= 2 && st <= 4) {
        st = 5;
        stopLeft = 4;
        rpmTarget = 0;
        fillOn = drainOn = soapOn = false;
      } else if (st == 1 || st == 6 || st == 7) {
        _off();
      }
      ok();
      return;
    }
    if (cmd == 'SEL') {
      final n = a.isEmpty ? 0 : (int.tryParse(a[0]) ?? 0);
      if (n < 1 || n > schema.n) return err('arg');
      if (st != 0 && st != 1) return err('busy');
      prog = n;
      st = 1;
      return ok();
    }
    if (cmd == 'ORDER') {
      if (a.isEmpty) return err('arg');
      if (st != 0 && st != 1) return err('busy');
      orderCode = a[0];
      orderOk = true;
      ok();
      emit('O,1,$orderCode');
      return;
    }
    if (cmd == 'ORDERCLR') {
      orderOk = false;
      orderCode = '';
      ok();
      emit('O,0,');
      return;
    }
    if (cmd == 'START') {
      if (params['remote_start'] != '1') return err('remote_start_off');
      if (st != 1 || prog == 0) return err('not_selected');
      if (params['order_req'] == '1' && !orderOk) return err('order_required');
      if (!dryer && !_learned) return err('motor_or_plan');
      _begin();
      return ok();
    }
    if (cmd == 'PAUSE') {
      if (st != 2) return err('state');
      st = 3;
      pausedTicks = 0;
      fillOn = drainOn = soapOn = false;
      rpmTarget = 0;
      gas = ign = false;
      heat = 0;
      return ok();
    }
    if (cmd == 'RESUME') {
      if ((st == 3 || st == 4) && !doorOpen) {
        st = 2;
        if (!dryer) lockRelay = true;
        return ok();
      }
      return err('state_or_door');
    }
    if (cmd == 'SET') {
      if (a.length < 2) return err('arg');
      if (!idle) return err('busy');
      final key = a[0].toLowerCase();
      if (key == 'pin') {
        pin = a[1];
        return ok();
      }
      if (!params.containsKey(key)) return err('key');
      final v = double.tryParse(a[1]);
      if (v == null) return err('arg');
      final meta = schema.meta(key);
      if (meta != null && (v < meta.min || v > meta.max)) return err('range');
      if (key == 'ntc_beta' && (v < 2500 || v > 4500)) return err('range');
      final old = params[key]!;
      final isFloat = (meta != null && !meta.isInt && !meta.isBool) || key == 'ntc_beta' || key == 'ntc_off';
      params[key] = isFloat ? v.toStringAsFixed(2) : v.round().toString();
      if (_check() != null) {
        params[key] = old;
        return err('constraint');
      }
      dirty = true;
      return ok();
    }
    if (cmd == 'PSET') {
      if (a.length < 1 + nf) return err('arg');
      if (!idle) return err('busy');
      final i = int.tryParse(a[0]) ?? 0;
      if (i < 1 || i > schema.n) return err('arg');
      final vals = <int>[];
      for (int k = 0; k < nf; k++) {
        final x = int.tryParse(a[1 + k]);
        if (x == null) return err('arg');
        vals.add(x);
      }
      final old = progs[i - 1];
      progs[i - 1] = vals;
      if (_check() != null) {
        progs[i - 1] = old;
        return err('constraint');
      }
      dirty = true;
      return ok();
    }
    if (cmd == 'RING') {
      if (a.length < schema.n) return err('arg');
      if (!idle) return err('busy');
      final r = [for (int k = 0; k < schema.n; k++) int.tryParse(a[k]) ?? 0];
      final seen = <int>{...r};
      if (seen.length != schema.n || r.any((x) => x < 1 || x > schema.n)) return err('constraint');
      ring = r;
      dirty = true;
      return ok();
    }
    if (cmd == 'NAME') {
      if (a.isEmpty) return err('arg');
      if (!idle) return err('busy');
      name = a.join(' ');
      dirty = true;
      return ok();
    }
    if (cmd == 'SAVE') {
      if (!idle) return err('busy');
      _saved = _snap();
      dirty = false;
      return ok();
    }
    if (cmd == 'LOAD') {
      if (!idle) return err('busy');
      _restore(_saved);
      dirty = false;
      return ok();
    }
    if (cmd == 'DEFAULTS') {
      if (!idle) return err('busy');
      final keep = <String, String>{for (final k in schema.deviceOwned) if (params[k] != null) k: params[k]!};
      params = Map<String, String>.of(schema.defParams)..addAll(keep);
      progs = [for (final p in schema.defProgs) List<int>.of(p)];
      ring = List<int>.of(schema.defRing);
      _saved = _snap();
      dirty = false;
      return ok();
    }
    if (cmd == 'CALREF' && dryer) {
      final ref = a.isEmpty ? null : double.tryParse(a[0]);
      if (ref == null) return err('arg');
      if (!idle) return err('busy');
      params['ntc_off'] = (ref - temp).toStringAsFixed(2);
      dirty = true;
      return ok();
    }
    if (!dryer && cmd == 'MLEARN') {
      if (st != 0 && st != 1) return err('busy');
      st = 8;
      testKind = 1;
      testLeft = 8;
      return ok();
    }
    if (!dryer && cmd == 'MTEST') {
      if (a.length < 3) return err('arg');
      if (st != 0 && st != 1) return err('busy');
      if (!_learned) return err('not_learned');
      st = 8;
      testKind = 2;
      testLeft = (int.tryParse(a[2]) ?? 5).clamp(3, 30).toInt();
      rpmTarget = (double.tryParse(a[1]) ?? 60).clamp(20, 250).toDouble();
      return ok();
    }
    if (!dryer && cmd == 'SOAP') {
      if (a.isEmpty) return err('arg');
      if (st != 0 && st != 1) return err('busy');
      st = 8;
      testKind = 3;
      testLeft = (int.tryParse(a[0]) ?? 5).clamp(1, 30).toInt();
      soapOn = true;
      return ok();
    }
    err('cmd');
  }

  // ---------------- dump konfigurasi (balasan GET) ----------------
  void _dump() {
    emit('V,demo-1.0,${dryer ? 'DRYER' : 'WASHER'}');
    for (final e in params.entries) {
      emit('C,${e.key},${e.value}');
    }
    for (int i = 0; i < schema.n; i++) {
      emit('P,${i + 1},${schema.progNames[i]},${progs[i].join(',')}');
    }
    emit('N,$name');
    emit('O,${orderOk ? 1 : 0},$orderCode');
    emit('R,${ring.join(',')}'); // R = penutup dump
    _status();
  }

  // ---------------- simulasi jalan ----------------
  void _begin() {
    final p = progs[prog - 1];
    elapsed = 0;
    unbalTries = 0;
    spinCap = 100000;
    if (dryer) {
      total = p[0] * 60;
      temp = 30;
    } else {
      wins = [];
      double t = 0;
      final hi = _pn('spin_hi_min'), fin = _pn('spin_fin_min');
      void add(String ty, double min) {
        if (min <= 0) return;
        wins.add(_Win(ty, t, t + min * 60));
        t += min * 60;
      }
      for (int c = 0; c < p[0]; c++) {
        if (p[1] > 0) add('wash', p[1].toDouble());
        for (int r = 0; r < p[2]; r++) {
          add('rinse', p[3].toDouble());
        }
        if (p[4] > 0) {
          add('sdrain', p[4] - hi);
          add('shigh', hi - fin);
          add('sfin', fin);
        }
      }
      total = t.round();
      lockRelay = true;
    }
    st = 2;
  }

  void _finish() {
    emit('E,DONE,$orderCode');
    st = 6;
    doneLeft = 8;
    rpmTarget = 0;
    gas = ign = fillOn = drainOn = soapOn = false;
    heat = 0;
    stage = 0;
    orderOk = false;
  }

  void _tick() {
    switch (st) {
      case 2:
        if (doorOpen) {
          st = 4;
          closedTicks = 0;
          fillOn = drainOn = soapOn = false;
          rpmTarget = 0;
          gas = ign = false;
          heat = 0;
          emit(dryer ? 'E,DOOR_OPEN' : 'E,LOCK_LOST');
        } else {
          elapsed += speed;
          if (elapsed >= total) {
            _finish();
          } else {
            dryer ? _dryerStep(speed.toDouble()) : _washerStep();
          }
        }
        break;
      case 3:
        pausedTicks++;
        if (!dryer && !levelFull && rpm < 5 && pausedTicks >= 3) lockRelay = false; // kunci dilepas hanya jika tanpa air dan drum diam
        break;
      case 4:
        if (!doorOpen) {
          closedTicks++;
          if (params['door_resume'] == '1' && closedTicks >= 2) {
            st = 2;
            if (!dryer) lockRelay = true;
          }
        }
        break;
      case 5:
        if (--stopLeft <= 0) _off();
        break;
      case 6:
        if (--doneLeft <= 0) {
          lockRelay = false;
          _off();
        }
        break;
      case 8:
        _testStep();
        break;
    }
    if (dryer && st != 2) {
      gas = false;
      temp = math.max(28, temp - 0.4 * (st == 5 ? speed / 4 : 1));
    }
    rpm += (rpmTarget - rpm) * 0.35;
    if (rpm < 0.5) rpm = 0;
    edges += rpm * 2.4;
    _status();
  }

  void _testStep() {
    if (testKind == 1) {
      rpmTarget = (testLeft % 2 == 0) ? 40 : 0;
    }
    if (--testLeft <= 0) {
      if (testKind == 1) {
        params['mot_ok'] = '1';
        params['mot_s'] = '0';
        params['mot_k'] = '2';
        dirty = true;
        emit('E,LEARN,OK,1,2,38');
      }
      soapOn = false;
      rpmTarget = 0;
      testKind = 0;
      st = 0;
    }
  }

  void _dryerStep(double dt) {
    final p = progs[prog - 1];
    final remain = total - elapsed;
    final heatOn = p[1] == 1;
    final cooling = heatOn && remain <= p[5];
    rpmTarget = 40;
    if (!heatOn || cooling) {
      heat = 0;
      gas = false;
      ign = false;
      temp = math.max(28, temp - 0.06 * dt);
      return;
    }
    final warm = _pn('ign_warm');
    final cyc = warm + p[2] + p[3];
    final t = elapsed % cyc;
    if (t < warm) {
      heat = 1;
      ign = true;
      gas = false;
      temp = math.max(28, temp - 0.04 * dt);
    } else if (t < warm + p[2]) {
      heat = 2;
      ign = true;
      gas = true;
      temp += 0.12 * dt;
    } else {
      heat = 0;
      ign = false;
      gas = false;
      temp = math.max(28, temp - 0.06 * dt);
    }
    temp = math.min(temp, p[4] + 2.0);
  }

  void _washerStep() {
    _Win? w;
    for (final x in wins) {
      if (elapsed >= x.start && elapsed < x.end) w = x;
    }
    if (w == null) return;
    final p = progs[prog - 1];
    final f = (elapsed - w.start) / (w.end - w.start);
    final dir = ((elapsed / 25).floor().isEven) ? 1 : -1;
    fillOn = drainOn = soapOn = false;
    switch (w.type) {
      case 'wash':
        if (f < 0.05) {
          stage = 2;
          soapOn = _pn('soap_en') == 1 && p[9] > 0;
          rpmTarget = 0;
        } else if (f < 0.25) {
          stage = 3;
          fillOn = f < 0.22;
          levelFull = f >= 0.22;
          rpmTarget = 0;
        } else {
          stage = 4;
          levelFull = true;
          rpmTarget = dir * p[7].toDouble();
        }
        break;
      case 'rinse':
        if (f < 0.15) {
          stage = 5;
          drainOn = true;
          levelFull = f < 0.08;
          rpmTarget = 0;
        } else if (f < 0.30) {
          stage = 3;
          fillOn = f < 0.27;
          levelFull = f >= 0.27;
          rpmTarget = 0;
        } else {
          stage = 4;
          levelFull = true;
          rpmTarget = dir * p[7].toDouble();
        }
        break;
      case 'sdrain':
        stage = 6;
        drainOn = true;
        levelFull = f < 0.3;
        rpmTarget = _pn('drain_rpm');
        break;
      case 'shigh':
        drainOn = true;
        levelFull = false;
        final top = math.min(p[8].toDouble(), spinCap);
        final bal = _pn('balance_rpm');
        if (f < 0.15) {
          stage = 7;
          rpmTarget = bal;
        } else if (f < 0.40) {
          stage = 9;
          rpmTarget = bal + (top - bal) * ((f - 0.15) / 0.25);
        } else {
          stage = 10;
          rpmTarget = top;
        }
        break;
      default:
        stage = 11;
        drainOn = true;
        levelFull = false;
        rpmTarget = _pn('finish_rpm');
    }
  }

  // ---------------- baris status ----------------
  void _status() {
    final act = st >= 2 && st <= 4;
    final rem = act ? math.max(0, total - elapsed).ceil() : 0;
    final d = dirty ? 1 : 0;
    if (dryer) {
      final off = _pn('ntc_off');
      final tExh = temp + off;
      final beta = _pn('ntc_beta') == 0 ? 3950.0 : _pn('ntc_beta');
      final ohm = (10000 * math.exp(beta * (1 / (temp + 273.15) - 1 / 298.15))).round();
      final cool = st == 2 && progs.isNotEmpty && prog > 0 && progs[prog - 1][1] == 1 && (total - elapsed) <= progs[prog - 1][5];
      emit('S,$st,$prog,$rem,$total,${(tExh * 10).round()},${(temp * 10).round()},$ohm,$heat,${gas ? 1 : 0},${ign ? 1 : 0},'
          '${st == 2 ? 1 : 0},${doorOpen ? 0 : 1},$fault,1,${cool ? 1 : 0},0,$d');
    } else {
      final motor = rpm > 1 ? 1 : 0;
      emit('S,$st,$prog,$rem,$total,${act ? stage : 0},${rpm.round()},${doorOpen ? 0 : (lockRelay ? 1 : 0)},${lockRelay ? 1 : 0},'
          '${levelFull ? 1 : 0},${fillOn ? 1 : 0},${drainOn ? 1 : 0},${soapOn ? 1 : 0},$motor,$fault,${_learned ? 1 : 0},$unbalTries,$d');
      emit('M,${(rpm * 10).round()},${(rpm * 1.2).round()},${edges.round()},${(edges.round() % 6) + 1},${rpm > 5 ? 40 : 0},1');
    }
    emit('O,${orderOk ? 1 : 0},$orderCode');
  }
}