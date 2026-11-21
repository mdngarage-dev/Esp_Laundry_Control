import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'machine_link.dart';
import 'models.dart';
import 'widgets.dart';

/// Gambar knob: OFF di atas, posisi 1..9 searah jarum jam (putar kanan). Ketuk posisi untuk mengganti program.
class KnobDial extends StatelessWidget {
  const KnobDial({super.key, required this.ring, required this.names, required this.onTapPos});
  final List<int> ring;
  final List<String> names;
  final void Function(int pos) onTapPos;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final size = math.min(c.maxWidth, 380.0);
      final cx = size / 2, cy = size / 2;
      final r = size / 2 - 38;
      final slots = <Widget>[];
      for (int k = 0; k < 10; k++) {
        final a = k * 2 * math.pi / 10;
        final x = cx + r * math.sin(a), y = cy - r * math.cos(a);
        final isOff = k == 0;
        slots.add(Positioned(
          left: x - 33, top: y - 25, width: 66, height: 50,
          child: Material(
            color: isOff ? th.colorScheme.errorContainer : th.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: isOff ? null : () => onTapPos(k),
              child: Center(
                child: isOff
                    ? const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.power_settings_new, size: 18), Text('OFF', style: TextStyle(fontSize: 10))])
                    : Padding(
                        padding: const EdgeInsets.all(2),
                        child: Text('$k\n${names[ring[k - 1] - 1]}', textAlign: TextAlign.center, maxLines: 3, style: const TextStyle(fontSize: 10, height: 1.1)),
                      ),
              ),
            ),
          ),
        ));
      }
      return Center(
        child: SizedBox(
          width: size, height: size,
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _DialPainter(th.colorScheme.outline, th.colorScheme.primary, r))),
            Positioned(
              left: cx - 55, top: cy - 30, width: 110,
              child: const Column(children: [
                Icon(Icons.rotate_right, size: 36),
                Text('putar KANAN\n= searah jarum jam', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
              ]),
            ),
            ...slots,
          ]),
        ),
      );
    });
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.track, this.arrow, this.r);
  final Color track, arrow;
  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, r, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = 2);
    // panah searah jarum jam di antara OFF dan posisi 1
    final a = math.pi / 10;
    final p = c + Offset(r * math.sin(a), -r * math.cos(a));
    final t = Offset(math.cos(a), math.sin(a));
    final u = Offset(math.sin(a), -math.cos(a));
    final path = Path()
      ..moveTo(p.dx + t.dx * 10, p.dy + t.dy * 10)
      ..lineTo(p.dx - t.dx * 4 + u.dx * 7, p.dy - t.dy * 4 + u.dy * 7)
      ..lineTo(p.dx - t.dx * 4 - u.dx * 7, p.dy - t.dy * 4 - u.dy * 7)
      ..close();
    canvas.drawPath(path, Paint()..color = arrow);
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) => old.track != track || old.arrow != arrow || old.r != r;
}

class KnobPage extends StatelessWidget {
  const KnobPage(this.m, {super.key});
  final MachineLink m;

  Future<void> _pick(BuildContext context, int pos) async {
    final ring = m.profile.ring;
    final names = m.profile.programs.map((p) => p.name).toList();
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text('Program di langkah putar $pos', style: Theme.of(c).textTheme.titleMedium)),
          for (int id = 1; id <= 9; id++)
            ListTile(
              title: Text(names[id - 1]),
              subtitle: ring.indexOf(id) + 1 == pos ? null : Text('sekarang di langkah ${ring.indexOf(id) + 1} (akan bertukar)'),
              trailing: ring[pos - 1] == id ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, id),
            ),
        ]),
      ),
    );
    if (chosen == null) return;
    final next = List<int>.of(ring);
    final cur = next.indexOf(chosen);
    final tmp = next[pos - 1];
    next[pos - 1] = chosen;
    next[cur] = tmp; // tukar agar tetap permutasi 1..9
    m.editRing(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Langkah knob rotary'),
        actions: [TextButton(onPressed: () => m.editRing(kDefaultRing), child: const Text('Default'))],
      ),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          final ring = m.profile.ring;
          final names = m.profile.programs.map((p) => p.name).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            SyncBanner(m),
            const Text('Ketuk satu langkah di gambar untuk mengganti programnya. Program yang dipilih akan bertukar tempat dengan yang tadinya di langkah itu. Berlaku di mesin setelah SYNC.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            KnobDial(ring: ring, names: names, onTapPos: (pos) => _pick(context, pos)),
            const SizedBox(height: 16),
            Text('Urutan putar kanan dari OFF', style: Theme.of(context).textTheme.titleMedium),
            for (int k = 0; k < 9; k++)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 14, child: Text('${k + 1}', style: const TextStyle(fontSize: 12))),
                title: Text(names[ring[k] - 1]),
              ),
            const SizedBox(height: 8),
            Text('Putar kiri 1 klik dari OFF langsung ke: ${names[ring[8] - 1]}'),
          ]);
        },
      ),
    );
  }
}
