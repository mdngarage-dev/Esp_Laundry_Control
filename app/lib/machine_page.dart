import 'package:flutter/material.dart';

import 'add_machine_page.dart';
import 'effects.dart';
import 'machine_link.dart';
import 'machine_settings_page.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_helpers.dart';
import 'widgets.dart';
import 'demo_panel.dart';

class MachinePage extends StatefulWidget {
  const MachinePage(this.m, {super.key});
  final MachineLink m;
  @override
  State<MachinePage> createState() => _MachinePageState();
}

class _MachinePageState extends State<MachinePage> {
  MachineLink get m => widget.m;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (m.phase == LinkPhase.idle && m.profile.deviceId != null) m.connect();
    });
  }

  Future<void> _run(Future<Reply> f) async {
    final r = await f;
    if (!r.ok && mounted) snack(context, errText(r.info));
  }

  String _dryerHeat(MachineStatus s) {
    if (s.prog < 1) return '';
    if (m.devPrograms[s.prog - 1].v[1] == 0 && m.configLoaded) return 'Angin (tanpa gas)';
    if (s.cooling) return 'Pendinginan';
    switch (s.heat) {
      case 1: return 'Igniter memanas';
      case 2: return s.gas ? 'Gas nyala' : 'Gas mati';
      case 3: return 'Coba lagi (purge)';
      default: return 'Gas mati (jeda siklus)';
    }
  }

  Widget _drum() {
    final p = pal(context);
    final progs = m.profile.programs;
    final name = m.progId >= 1 && m.progId <= progs.length ? progs[m.progId - 1].name : '-';
    final active = m.stateCode == 2;
    String sub, info;
    bool hot = false;
    double fill = 0, rpm = 0;
    if (m.isDryer) {
      final s = m.status!;
      info = s.sensorOk ? '${s.temp.toStringAsFixed(1)} °C' : 'Sensor bermasalah';
      sub = s.running ? _dryerHeat(s) : s.stateText;
      hot = s.gas;
      rpm = s.motor ? 300 : 0;
    } else {
      final w = m.wstatus!;
      info = w.motor ? '${w.rpm} rpm' : (w.levelFull ? 'Air penuh' : '');
      sub = w.running ? w.stageText : w.stateText;
      fill = w.levelFull ? 0.72 : (w.fill ? 0.4 : 0);
      rpm = w.rpm.toDouble();
    }
    return Center(
      child: NeuBox(
        circle: true,
        padding: const EdgeInsets.all(14),
        child: RunEffect(
          washer: !m.isDryer, active: active, fill: fill, hot: hot, rpm: rpm, size: 280,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(m.running ? fmtTime(m.remainS) : '--:--', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: p.text)),
            Text(name, style: TextStyle(fontSize: 16, color: p.accent, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(info, style: TextStyle(color: p.text, fontSize: 15)),
            Text(sub, textAlign: TextAlign.center, style: TextStyle(color: p.sub, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _flag(String label, bool on) {
    final p = pal(context);
    return NeuBox(
      radius: 14, depth: 0.5, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(on ? Icons.check_circle : Icons.circle_outlined, size: 14, color: on ? Colors.green : p.sub),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: p.text)),
      ]),
    );
  }

  Widget _connectCard() {
    final p = pal(context);
    final busy = m.phase == LinkPhase.connecting || m.phase == LinkPhase.authing;
    return NeuBox(
      child: Column(children: [
        Icon(Icons.bluetooth_disabled, size: 40, color: p.sub),
        const SizedBox(height: 8),
        Text(busy ? 'Menghubungkan...' : m.profile.deviceId == null ? 'ESP32 belum dipasangkan' : 'Mesin offline', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
        if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
        if (m.lastError != null && !busy)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(m.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 12),
        if (!busy)
          m.profile.deviceId == null
              ? FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PairPage(m))), icon: const Icon(Icons.link), label: const Text('Pasangkan ESP32'))
              : FilledButton.icon(onPressed: m.connect, icon: const Icon(Icons.bluetooth), label: const Text('Hubungkan')),
        const SizedBox(height: 8),
        Text('Setting tetap bisa diatur lewat tombol ⚙ dan disinkron nanti.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.sub)),
      ]),
    );
  }

  List<Widget> _control() {
    final p = pal(context);
    final code = m.stateCode;
    final selecting = code == 0 || code == 1;
    final active = m.running;
    final lockOk = m.isDryer ? m.status!.door : m.wstatus!.lockContact;
    final canStart = m.devRemoteStart && code == 1 && m.progId > 0 && (!m.devOrderReq || m.orderOk);
    final canResume = code == 3 || (code == 4 && lockOk);
    final fault = m.isDryer ? m.status!.fault : m.wstatus!.fault;
    final progs = m.profile.programs;

    return [
      _drum(),
      const SizedBox(height: 14),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: m.isDryer
          ? [_flag('Pintu tertutup', m.status!.door), _flag('Motor', m.status!.motor), _flag('Igniter', m.status!.ign), _flag('Gas', m.status!.gas)]
          : [_flag('Pintu terkunci', m.wstatus!.lockContact), _flag('Air penuh', m.wstatus!.levelFull), _flag('Isi air', m.wstatus!.fill),
              _flag('Buang air', m.wstatus!.drain), _flag('Sabun', m.wstatus!.soap), _flag('Motor', m.wstatus!.motor)]),
      if (code == 7)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('E$fault: ${m.isDryer ? faultText(fault) : washerFaultText(fault)}',
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      if (!m.isDryer && !m.wstatus!.learned)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: NeuBox(selected: true, child: Text('Motor belum dipelajari. Buka ⚙ > Kalibrasi motor dan sabun > Pelajari motor, sebelum menjalankan program.', style: TextStyle(color: p.text, fontSize: 13))),
        ),
      if (code == 4)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: NeuBox(selected: true, child: Text(!lockOk ? 'Kontak kunci terlepas - menunggu pintu terkunci kembali' : m.devDoorResume ? 'Kunci OK, melanjutkan...' : 'Kunci OK - tekan LANJUT', style: TextStyle(color: p.text))),
        ),
      if (code == 3 && !m.isDryer)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: NeuBox(child: Text(m.wstatus!.lockRelay ? 'Dijeda. Pintu tetap terkunci (ada air / drum masih berputar).' : 'Dijeda. Kunci dilepas - pintu terbuka dalam 1-3 menit.', style: TextStyle(color: p.text, fontSize: 13))),
        ),
      OrderCard(m),
      if (selecting) ...[
        const SizedBox(height: 18),
        Text('Pilih program', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SizedBox(
          height: 64,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (int i = 0; i < progs.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 8, left: 4),
                child: NeuBox(
                  radius: 16,
                  selected: code == 1 && m.progId == i + 1,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onTap: () => _run(m.selectProgram(i + 1)),
                  child: Center(child: Text(progs[i].name, style: TextStyle(color: p.text, fontWeight: FontWeight.w600))),
                ),
              ),
          ]),
        ),
        if (code == 1 && m.progId >= 1)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(m.schema.summary(m.devPrograms[m.progId - 1]), style: TextStyle(color: p.sub, fontSize: 12))),
      ],
      const SizedBox(height: 18),
      Row(children: [
        if (selecting)
          Expanded(
            child: NeuButton(
              icon: Icons.play_arrow, label: 'MULAI',
              onTap: canStart
                  ? () async {
                      final ok = await confirm(context, 'Mulai?', m.isDryer ? 'Pastikan pintu tertutup, area sekitar mesin aman, dan tidak ada bau gas.' : 'Pastikan pintu tertutup dan drum berisi cucian yang benar.', ok: 'MULAI');
                      if (ok && mounted) _run(m.startRun());
                    }
                  : null,
            ),
          ),
        if (active)
          Expanded(
            child: NeuButton(
              icon: code == 2 ? Icons.pause : Icons.play_arrow, label: code == 2 ? 'JEDA' : 'LANJUT',
              onTap: code == 2 ? () => _run(m.pause()) : canResume ? () => _run(m.resume()) : null,
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: NeuButton(
            icon: Icons.stop, label: active ? 'STOP' : 'MATIKAN',
            onTap: code == 0
                ? null
                : () async {
                    final ok = await confirm(context, active ? 'Stop program?' : 'Matikan mesin?',
                        active ? (m.isDryer ? 'Gas dimatikan, motor mendinginkan lalu mesin OFF.' : 'Motor berhenti, air dibuang sampai kosong, lalu mesin OFF.') : 'Layar dan mesin dimatikan.', ok: 'STOP');
                    if (ok && mounted) _run(m.stop());
                  },
          ),
        ),
      ]),
      if (selecting && !m.devRemoteStart)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Mulai dari HP dimatikan. Tekan knob di mesin untuk memulai, atau aktifkan di ⚙ > Pengaturan umum, lalu SYNC.', style: TextStyle(fontSize: 12, color: p.sub)),
        ),
      const SizedBox(height: 22),
      NeuButton(icon: Icons.warning_amber, label: 'TAHAN = MATI DARURAT', color: Theme.of(context).colorScheme.error,
          onTap: () => snack(context, 'Tahan tombol 1 detik untuk MATI DARURAT'), onLongPress: () => _run(m.emergency())),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(m.profile.name),
            actions: [
              const ThemeToggle(),
              IconButton(
                tooltip: m.isReady ? 'Putuskan' : 'Hubungkan',
                icon: Icon(m.isReady ? Icons.bluetooth_connected : Icons.bluetooth),
                onPressed: m.profile.deviceId == null ? null : (m.isReady ? m.disconnect : m.connect),
              ),
              IconButton(tooltip: 'Pengaturan', icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MachineSettingsPage(m)))),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            SyncBanner(m),
            if (m.isDemo) DemoPanel(m),
            if (!m.isReady || !m.hasStatus) _connectCard() else ..._control(),
          ]),
        );
      },
    );
  }
}
