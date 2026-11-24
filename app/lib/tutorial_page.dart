import 'package:flutter/material.dart';

import 'theme.dart';
import 'tutorial_data.dart';
import 'ui_helpers.dart';

/// Panduan sambungan soket PCB1. type: 'dryer' atau 'washer' (isi menyesuaikan mesin yang dibuka).
class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key, required this.type});
  final String type;

  bool get dryer => type == 'dryer';
  String get machine => dryer ? 'Dryer' : 'Mesin Cuci';
  UseDef? _use(SocketDef s) => dryer ? s.dryer : s.washer;

  bool _unexplained(SocketDef s) => (_use(s)?.name.startsWith('Belum ada') ?? false);
  bool _used(SocketDef s) {
    final u = _use(s);
    return u != null && !_unexplained(s) && u.connect.isNotEmpty && u.connect.first != 'Biarkan kosong.';
  }

  Color _kindColor(String k) => k == 'mains' ? Colors.red : (k == 'hv' ? Colors.deepOrange : Colors.teal);
  String _kindText(String k) => k == 'mains' ? 'Listrik 220 V' : (k == 'hv' ? 'Tegangan tinggi (motor)' : 'Tegangan rendah');

  // ---------------- komponen kecil ----------------
  Widget _h(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t, style: TextStyle(color: pal(context).accent, fontWeight: FontWeight.w800, fontSize: 14)),
      );

  Widget _lines(BuildContext context, List<String> items, {bool numbered = false}) {
    final p = pal(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (int i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text(numbered ? '${i + 1}.' : '•', style: TextStyle(color: p.sub))),
            Expanded(child: Text(items[i], style: TextStyle(color: p.text, height: 1.35))),
          ]),
        ),
    ]);
  }

  Widget _dot(BuildContext context, SocketDef s) {
    final used = _used(s);
    final c = used ? _kindColor(s.kind) : Colors.grey;
    return GestureDetector(
      onTap: () => _detail(context, s),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(3)),
          child: Text(s.id, style: const TextStyle(fontSize: 8, color: Colors.white)),
        ),
      ]),
    );
  }

  Widget _map(BuildContext context) {
    return NeuBox(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 457 / 431,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth, h = c.maxHeight;
              return GestureDetector(
                onLongPressStart: (d) => snack(context, 'Koordinat: x=${(d.localPosition.dx / w).toStringAsFixed(3)}, y=${(d.localPosition.dy / h).toStringAsFixed(3)}'),
                child: Stack(children: [
                  Positioned.fill(child: Image.asset('assets/tutorial/board_3d.png', fit: BoxFit.fill)),
                  for (final s in kSockets)
                    Positioned(left: s.x * w - 16, top: s.y * h - 7, width: 32, child: _dot(context, s)),
                ]),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _legendItem(BuildContext context, Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(color: pal(context).sub, fontSize: 11)),
      ]);

  // ---------------- detail satu soket ----------------
  void _detail(BuildContext context, SocketDef s) {
    final p = pal(context);
    final u = _use(s);
    final used = _used(s);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (c, ctl) => ListView(controller: ctl, padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
          Row(children: [
            Expanded(child: Text('${s.id}  -  ${s.title}', style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 17))),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            Chip(
              label: Text(_kindText(s.kind), style: const TextStyle(color: Colors.white, fontSize: 11)),
              backgroundColor: _kindColor(s.kind),
              visualDensity: VisualDensity.compact,
            ),
            Chip(label: Text(used ? 'Dipakai di $machine' : (u == null ? 'Tidak ada di $machine' : 'Tidak dipakai di $machine'), style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 6),
          Text('Lokasi di papan: ${s.where}', style: TextStyle(color: p.sub, fontSize: 12)),
          if (s.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: NeuBox(selected: true, child: Text(s.note!, style: TextStyle(color: p.text, fontSize: 12.5, height: 1.35))),
            ),
          _h(context, 'Pin (dilihat dari atas, pin 1 di sisi kiri atau atas papan)'),
          NeuBox(
            depth: 0.5,
            child: Column(children: [
              for (final pin in s.pins)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 44, child: Text('Pin ${pin.no}', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontSize: 12))),
                    SizedBox(width: 92, child: Text(pin.net, style: TextStyle(color: p.sub, fontSize: 12))),
                    Expanded(child: Text(pin.fn, style: TextStyle(color: p.text, fontSize: 12))),
                  ]),
                ),
            ]),
          ),
          if (u == null)
            Padding(padding: const EdgeInsets.only(top: 16), child: Text('Soket atau komponen ini tidak dipakai di $machine. Biarkan kosong.', style: TextStyle(color: p.text)))
          else ...[
            _h(context, 'Disambung ke: ${u.name}'),
            _lines(context, u.connect, numbered: used),
            if (u.trace.isNotEmpty) ...[
              _h(context, 'Cara menyusuri kabel (tiap mesin berbeda)'),
              _lines(context, u.trace),
            ],
            if (u.warn.isNotEmpty) ...[
              _h(context, 'Peringatan'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withAlpha(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withAlpha(90))),
                child: _lines(context, u.warn),
              ),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _tile(BuildContext context, SocketDef s) {
    final p = pal(context);
    final u = _use(s);
    final used = _used(s);
    final c = used ? _kindColor(s.kind) : Colors.grey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeuBox(
        onTap: () => _detail(context, s),
        child: Row(children: [
          Container(width: 6, height: 40, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.id}  -  ${u?.name ?? s.title}', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
              Text(s.where, style: TextStyle(color: p.sub, fontSize: 11)),
            ]),
          ),
          Icon(Icons.chevron_right, color: p.sub),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final usedList = kSockets.where(_used).toList();
    const order = {'mains': 0, 'hv': 1, 'low': 2};
    usedList.sort((a, b) => (order[a.kind] ?? 9).compareTo(order[b.kind] ?? 9));
    final others = kSockets.where((s) => !_used(s)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Panduan soket: $machine'), actions: const [ThemeToggle()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        NeuBox(
          selected: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 8),
              Text('Baca dulu: keselamatan', style: TextStyle(color: p.text, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            _lines(context, kSafety),
          ]),
        ),
        const SizedBox(height: 16),
        _map(context),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _legendItem(context, Colors.red, '220 V'),
          _legendItem(context, Colors.deepOrange, 'Motor (tinggi)'),
          _legendItem(context, Colors.teal, 'Tegangan rendah'),
          _legendItem(context, Colors.grey, 'Tidak dipakai'),
        ]),
        const SizedBox(height: 4),
        Text('Cubit untuk memperbesar, ketuk titik untuk detail. Titik kurang pas? Tahan lama di peta untuk membaca koordinatnya.', style: TextStyle(color: p.sub, fontSize: 11)),
        _h(context, 'Soket yang dipakai di $machine'),
        for (final s in usedList) _tile(context, s),
        _h(context, 'Soket lain (kosongkan)'),
        for (final s in others) _tile(context, s),
        _h(context, 'Urutan uji setelah tersambung'),
        NeuBox(child: _lines(context, dryer ? kTestDryer : kTestWasher)),
        const SizedBox(height: 24),
      ]),
    );
  }
}
