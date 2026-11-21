import 'package:flutter/material.dart';

import 'dryer_link.dart';
import 'models.dart';
import 'ui_helpers.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _run(BuildContext c, Future<Reply> f) async {
    final r = await f;
    if (!r.ok && c.mounted) snack(c, errText(r.info));
  }

  String _heatText(MachineStatus s) {
    if (s.prog < 1) return '';
    final p = link.programs[s.prog - 1];
    if (p.heat == 0 && link.configLoaded) return 'Angin (tanpa gas)';
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final s = link.status;
        if (s == null) return const Center(child: CircularProgressIndicator());
        final th = Theme.of(context);
        final selecting = s.state == 0 || s.state == 1;
        final active = s.state >= 2 && s.state <= 5;
        final progName = s.prog >= 1 ? link.programs[s.prog - 1].name : '-';
        final progress = s.totalS > 0 ? ((s.totalS - s.remainS) / s.totalS).clamp(0.0, 1.0) : 0.0;
        final canStart = link.remoteStartOn && s.state == 1 && s.prog > 0;
        final canResume = s.state == 3 || (s.state == 4 && s.door);

        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text(s.stateText, style: th.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(active ? fmtTime(s.remainS) : '--:--', style: th.textTheme.displayLarge),
                Text(progName, style: th.textTheme.titleLarge),
                if (active) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: progress, minHeight: 8),
                ],
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
            _flag('Pintu tertutup', s.door),
            _flag('Motor', s.motor),
            _flag('Igniter', s.ign),
            _flag('Gas', s.gas),
          ]),
          if (s.state == 4)
            Card(
              color: th.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(!s.door
                    ? 'Pintu terbuka - tutup pintu untuk melanjutkan'
                    : link.doorResumeOn ? 'Pintu ditutup, melanjutkan...' : 'Pintu tertutup - tekan LANJUT'),
              ),
            ),
          if (selecting) ...[
            const SizedBox(height: 16),
            Text('Pilih program', style: th.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (int i = 0; i < 9; i++)
                ChoiceChip(
                  label: Text(link.programs[i].name),
                  selected: s.state == 1 && s.prog == i + 1,
                  onSelected: (_) => _run(context, link.selectProgram(i + 1)),
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
                          final ok = await confirm(context, 'Mulai pengeringan?',
                              'Pastikan pintu tertutup, area sekitar mesin aman, dan tidak ada bau gas.', ok: 'MULAI');
                          if (ok && context.mounted) _run(context, link.startRun());
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('MULAI'),
                ),
              ),
            if (active)
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: s.state == 2
                      ? () => _run(context, link.pause())
                      : canResume ? () => _run(context, link.resume()) : null,
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
                            active ? 'Gas dimatikan, motor tetap berputar mendinginkan lalu mesin OFF.' : 'Layar dan mesin dimatikan.',
                            ok: 'STOP');
                        if (ok && context.mounted) _run(context, link.stop());
                      },
                icon: const Icon(Icons.stop),
                label: Text(active ? 'STOP' : 'MATIKAN'),
              ),
            ),
          ]),
          if (selecting && !link.remoteStartOn)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Mulai dari HP dimatikan. Tekan knob di mesin untuk memulai, atau aktifkan di Setting > "Izinkan mulai dari HP".',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: th.colorScheme.error, foregroundColor: th.colorScheme.onError),
            onPressed: () => snack(context, 'Tahan tombol 1 detik untuk MATI DARURAT'),
            onLongPress: () => _run(context, link.emergency()),
            icon: const Icon(Icons.warning_amber),
            label: const Text('TAHAN = MATI DARURAT'),
          ),
        ]);
      },
    );
  }
}
