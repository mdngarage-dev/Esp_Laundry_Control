import 'package:flutter/material.dart';

import 'order_service.dart';
import 'theme.dart';
import 'ui_helpers.dart';

/// Pengaturan integrasi Firebase laundry: login, nama pelanggan dari nomor order, update status order.
class OrderSettingsPage extends StatefulWidget {
  const OrderSettingsPage({super.key});
  @override
  State<OrderSettingsPage> createState() => _OrderSettingsPageState();
}

class _OrderSettingsPageState extends State<OrderSettingsPage> {
  final testCtl = TextEditingController();
  String testResult = '';

  @override
  void dispose() {
    testCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Order & Firebase (tanpa login)'), actions: const [ThemeToggle()]),
      body: ListenableBuilder(
        listenable: orders,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          NeuBox(
            child: Row(children: [
              Icon(orders.ready ? Icons.cloud_done : Icons.cloud_off, color: orders.ready ? Colors.green : p.sub),
              const SizedBox(width: 12),
              Expanded(
                child: Text(orders.ready ? 'Firebase terhubung' : 'Firebase belum dikonfigurasi.\nJalankan "flutterfire configure" (lihat README).', style: TextStyle(color: p.text)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          NeuBox(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Ubah status order saat mesin mulai', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
              subtitle: Text('Status "$kStatusQueued" diubah ke "$kStatusProcessing" ketika mesin mulai berjalan dengan order yang di-scan. Hanya jika status masih "$kStatusQueued", jadi mesin kedua tidak menimpa. Tahap lain tetap manual oleh operator.', style: TextStyle(color: p.sub, fontSize: 12)),
              value: orders.writeStatus,
              onChanged: orders.setWriteStatus,
            ),
          ),
          if (orders.pending.isNotEmpty) ...[
            const SizedBox(height: 16),
            NeuBox(
              selected: true,
              child: Row(children: [
                Expanded(child: Text('Menunggu dikirim ke Firestore: ${orders.pending.join(', ')}', style: TextStyle(color: p.text))),
                TextButton(onPressed: orders.flushPending, child: const Text('Kirim ulang')),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          NeuBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Uji cari nama dari nomor order', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: testCtl, decoration: const InputDecoration(labelText: 'Nomor order (mis. MDN261121186)', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final code = testCtl.text.trim();
                    if (code.isEmpty) return;
                    final i = await orders.lookup(code);
                    if (!mounted) return;
                    setState(() => testResult = i == null ? (orders.lastError ?? 'Tidak ditemukan') : 'Nama: ${i.name.isEmpty ? '(kosong)' : i.name}   •   status: ${i.status}');
                  },
                  child: const Text('Cari'),
                ),
              ]),
              if (testResult.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(testResult, style: TextStyle(color: p.text))),
            ]),
          ),
        ]),
      ),
    );
  }
}
