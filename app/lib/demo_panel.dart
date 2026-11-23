import 'package:flutter/material.dart';

import 'machine_link.dart';
import 'theme.dart';

/// Panel kendali simulasi (hanya muncul di mesin DEMO): buka pintu, percepat waktu, picu error, selesaikan cepat.
class DemoPanel extends StatefulWidget {
  const DemoPanel(this.m, {super.key});
  final MachineLink m;
  @override
  State<DemoPanel> createState() => _DemoPanelState();
}

class _DemoPanelState extends State<DemoPanel> {
  @override
  Widget build(BuildContext context) {
    final d = widget.m.demo;
    if (d == null) return const SizedBox.shrink();
    final p = pal(context);
    final washer = !widget.m.isDryer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: NeuBox(
        selected: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('MODE DEMO (simulasi, bukan ESP32 asli)', style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 8),
          Text('Kecepatan waktu', style: TextStyle(color: p.sub, fontSize: 11)),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('x1')),
              ButtonSegment(value: 20, label: Text('x20')),
              ButtonSegment(value: 60, label: Text('x60')),
              ButtonSegment(value: 200, label: Text('x200')),
            ],
            selected: {d.speed},
            onSelectionChanged: (s) => setState(() => d.speed = s.first),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilterChip(
              label: Text(washer ? 'Kontak kunci lepas' : 'Pintu terbuka'),
              selected: d.doorOpen,
              onSelected: (v) => setState(() => d.setDoorOpen(v)),
            ),
            ActionChip(label: const Text('Selesaikan cepat'), onPressed: d.skipToEnd),
            if (washer) ActionChip(label: const Text('Picu air tidak masuk (E5)'), onPressed: () => d.injectFault(5)),
            if (washer) ActionChip(label: const Text('Beban tidak seimbang'), onPressed: d.injectUnbal),
            if (!washer) ActionChip(label: const Text('Picu suhu terlalu panas (E2)'), onPressed: () => d.injectFault(2)),
          ]),
          const SizedBox(height: 6),
          Text(
              washer
                  ? 'Tips: aktifkan "Izinkan mulai dari HP" di ⚙ lalu SYNC; jalankan "Pelajari motor" di ⚙ > Kalibrasi sebelum MULAI.'
                  : 'Tips: aktifkan "Izinkan mulai dari HP" di ⚙ lalu SYNC, baru tombol MULAI aktif.',
              style: TextStyle(color: p.sub, fontSize: 11)),
        ]),
      ),
    );
  }
}