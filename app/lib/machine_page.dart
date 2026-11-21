import 'package:flutter/material.dart';

import 'add_machine_page.dart';
import 'machine_link.dart';
import 'machine_settings_page.dart';
import 'models.dart';
import 'ui_helpers.dart';
import 'widgets.dart';

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

  String _heatText(MachineStatus s) {
    if (s.prog < 1) return '';
    final p = m.devPrograms[s.prog - 1];
    if (p.heat == 0 && m.configLoaded) return 'Angin (tanpa gas)';
    if (s.cooling) return 'Pendinginan';
    switch (s.heat) {
      case 1: return 'Igniter memanas';
      case 2: return s.gas ? 'Gas nyala' : 'Gas mati';
      case 3: return 'Coba lagi (purge)';
      default: return 'Gas mati (jeda siklus)';
    }
  }

  Widget _flag(String label, bool on) => Chip(
        avatar: Icon(on ? Icons.check_circle : Icons.circle_outlined, size: 16),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      );

  Widget _connectCard() {
    final th = Theme.of(context);
    final busy = m.phase == LinkPhase.connecting || m.phase == LinkPhase.authing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Icon(Icons.bluetooth_disabled, size: 40),
          const SizedBox(height: 8),
          Text(busy ? 'Menghubungkan...' : m.profile.deviceId == null ? 'ESP32 belum dipasangkan' : 'Mesin offline', style: th.textTheme.titleMedium),
          if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          if (m.lastError != null && !busy)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(m.lastError!, style: TextStyle(color: th.colorScheme.error))),
          const SizedBox(height: 12),
          if (!busy)
            m.profile.deviceId == null
                ? FilledButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PairPage(m))),
                    icon: const Icon(Icons.link),
                    label: const Text('Pasangkan ESP32'))
                : FilledButton.icon(onPressed: m.connect, icon: const Icon(Icons.bluetooth), label: const Text('Hubungkan')),
          const SizedBox(height: 8),
          const Text('Setting tetap bisa diatur lewat tombol ⚙ dan disinkron nanti saat terhubung.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  List<Widget> _control(MachineStatus s) {
    final th = Theme.of(context);
    final selecting = s.state == 0 || s.state == 1;
    final active = s.running;
    final progName = s.prog >= 1 ? m.profile.programs[s.prog - 1].name : '-';
    final progress = s.totalS > 0 ? ((s.totalS - s.remainS) / s.totalS).clamp(0.0, 1.0) : 0.0;
    final canStart = m.devRemoteStart && s.state == 1 && s.prog > 0;
    final canResume = s.state == 3 || (s.state == 4 && s.door);
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(s.stateText, style: th.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(active ? fmtTime(s.remainS) : '--:--', style: th.textTheme.displayLarge),
            Text(progName, style: th.textTheme.titleLarge),
            if (active) ...[const SizedBox(height: 12), LinearProgressIndicator(value: progress, minHeight: 8)],
            const SizedBox(height: 12),
            Text(s.sensorOk ? '${s.temp.toStringAsFixed(1)} °C' : 'Sensor suhu bermasalah', style: th.textTheme.headlineSmall),
            if (active) Text(_heatText(s)),
            if (s.state == 7)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('E${s.fault}: ${faultText(s.fault)}', style: TextStyle(color: th.colorScheme.error, fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        _flag('Pintu tertutup', s.door), _flag('Motor', s.motor), _flag('Igniter', s.ign), _flag('Gas', s.gas),
      ]),
      if (s.state == 4)
        Card(
          color: th.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(!s.door
                ? 'Pintu terbuka - tutup pintu untuk melanjutkan'
                : m.devDoorResume ? 'Pintu ditutup, melanjutkan...' : 'Pintu tertutup - tekan LANJUT'),
          ),
        ),
      if (selecting) ...[
        const SizedBox(height: 16),
        Text('Pilih program', style: th.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (int i = 0; i < 9; i++)
            ChoiceChip(
              label: Text(m.profile.programs[i].name),
              selected: s.state == 1 && s.prog == i + 1,
              onSelected: (_) => _run(m.selectProgram(i + 1)),
            ),
        ]),
      ],
      const SizedBox(height: 16),
      Row(children: [
        if (selecting)
          Expanded(
            child: FilledButton.icon(
              onPressed: canStart
                  ? () async {
                      final ok = await confirm(context, 'Mulai pengeringan?', 'Pastikan pintu tertutup, area sekitar mesin aman, dan tidak ada bau gas.', ok: 'MULAI');
                      if (ok && mounted) _run(m.startRun());
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('MULAI'),
            ),
          ),
        if (active)
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: s.state == 2 ? () => _run(m.pause()) : canResume ? () => _run(m.resume()) : null,
              icon: Icon(s.state == 2 ? Icons.pause : Icons.play_arrow),
              label: Text(s.state == 2 ? 'JEDA' : 'LANJUT'),
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: s.state == 0
                ? null
                : () async {
                    final ok = await confirm(context, active ? 'Stop pengeringan?' : 'Matikan mesin?',
                        active ? 'Gas dimatikan, motor tetap berputar mendinginkan lalu mesin OFF.' : 'Layar dan mesin dimatikan.', ok: 'STOP');
                    if (ok && mounted) _run(m.stop());
                  },
            icon: const Icon(Icons.stop),
            label: Text(active ? 'STOP' : 'MATIKAN'),
          ),
        ),
      ]),
      if (selecting && !m.devRemoteStart)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Mulai dari HP dimatikan. Tekan knob di mesin untuk memulai, atau aktifkan di ⚙ > Pengaturan umum, lalu SYNC.', style: TextStyle(fontSize: 12)),
        ),
      const SizedBox(height: 24),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: th.colorScheme.error, foregroundColor: th.colorScheme.onError),
        onPressed: () => snack(context, 'Tahan tombol 1 detik untuk MATI DARURAT'),
        onLongPress: () => _run(m.emergency()),
        icon: const Icon(Icons.warning_amber),
        label: const Text('TAHAN = MATI DARURAT'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final s = m.status;
        final isDryer = m.profile.type == 'dryer';
        return Scaffold(
          appBar: AppBar(
            title: Text(m.profile.name),
            actions: [
              IconButton(
                tooltip: m.isReady ? 'Putuskan' : 'Hubungkan',
                icon: Icon(m.isReady ? Icons.bluetooth_connected : Icons.bluetooth),
                onPressed: m.profile.deviceId == null ? null : (m.isReady ? m.disconnect : m.connect),
              ),
              IconButton(
                tooltip: 'Pengaturan',
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MachineSettingsPage(m))),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            if (!isDryer)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Kontrol mesin cuci belum tersedia (firmware mesin cuci belum dibuat). '
                      'Nama dan ESP32 bisa disiapkan dulu lewat ⚙.'),
                ),
              )
            else ...[
              SyncBanner(m),
              if (!m.isReady || s == null) _connectCard() else ..._control(s),
            ],
          ]),
        );
      },
    );
  }
}
