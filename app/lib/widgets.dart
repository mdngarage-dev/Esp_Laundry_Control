import 'package:flutter/material.dart';

import 'machine_link.dart';
import 'order_service.dart';
import 'scan_page.dart';
import 'theme.dart';
import 'ui_helpers.dart';

Future<void> doSync(BuildContext c, MachineLink m) async {
  final err = await m.sync();
  if (c.mounted) snack(c, err ?? 'Tersinkron dan tersimpan permanen di mesin');
}

/// Barcode: hanya huruf/angka/-/_/. (maks 31) yang diterima mesin.
String? cleanOrder(String raw) {
  final t = raw.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '');
  return (t.isEmpty || t.length > 31) ? null : t;
}

/// Huruf besar ASCII untuk layar I2C: huruf, angka, spasi, titik, minus (yang lain dibuang).
String asciiClean(String s) {
  final b = StringBuffer();
  for (final r in s.toUpperCase().runes) {
    final ch = String.fromCharCode(r);
    if (RegExp(r'[A-Z0-9 .\-]').hasMatch(ch)) b.write(ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

Future<void> scanOrder(BuildContext c, MachineLink m) async {
  final raw = await Navigator.push<String>(c, MaterialPageRoute(builder: (_) => const ScanPage()));
  if (raw == null || !c.mounted) return;
  final code = cleanOrder(raw);
  if (code == null) {
    snack(c, 'Barcode tidak valid (kosong atau lebih dari 31 karakter): "$raw"');
    return;
  }
  snack(c, 'Mencari nama pelanggan untuk $code ...');
  final info = await orders.lookup(code); // null jika offline / belum dikonfigurasi / order tidak ada
  final name = asciiClean(info?.name ?? '');
  final room = 46 - code.length - 3;
  final shown = name.isEmpty ? '' : '${name.length > room ? name.substring(0, room) : name} - $code';
  final r = await m.sendOrder(code, shown);
  if (!c.mounted) return;
  if (!r.ok) {
    snack(c, errText(r.info));
    return;
  }
  final note = name.isEmpty ? '${orders.lastError ?? 'Nama tidak ditemukan'}. Layar mesin menampilkan nomor order.' : 'Pelanggan: $name.';
  // Scan langsung jalan: mengikuti setting "Izinkan mulai dari HP" (remote_start), program harus sudah dipilih.
  if (m.devRemoteStart && m.stateCode == 1 && m.progId > 0) {
    final s = await m.startRun();
    if (c.mounted) snack(c, s.ok ? 'Order $code - mesin dijalankan. $note' : '${errText(s.info)}. $note');
  } else {
    snack(c, 'Order $code siap. $note ${m.devRemoteStart ? 'Pilih program lalu tekan MULAI.' : 'Tekan MULAI di mesin / aplikasi.'}');
  }
}

/// Kartu barcode order: tampil jika fitur dipakai (order_req aktif di mesin) atau order sudah di-scan.
class OrderCard extends StatelessWidget {
  const OrderCard(this.m, {super.key});
  final MachineLink m;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        if (!m.isReady || !(m.devOrderReq || m.orderOk)) return const SizedBox.shrink();
        final p = pal(context);
        final canScan = m.stateCode == 0 || m.stateCode == 1;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: NeuBox(
            child: Row(children: [
              Icon(m.orderOk ? Icons.verified : Icons.qr_code_scanner, color: m.orderOk ? Colors.green : p.accent, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.orderOk ? 'Order ${m.orderCode}' : 'Scan barcode order dulu', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                  Text(m.orderOk ? 'Siap dijalankan' : 'Mesin tidak mau mulai sebelum order di-scan', style: TextStyle(color: p.sub, fontSize: 12)),
                ]),
              ),
              if (canScan)
                FilledButton(onPressed: () => scanOrder(context, m), child: Text(m.orderOk ? 'Ganti' : 'Scan')),
              if (canScan && m.orderOk) IconButton(onPressed: m.clearOrder, icon: const Icon(Icons.close)),
            ]),
          ),
        );
      },
    );
  }
}

/// Banner status sinkronisasi + keputusan saat draft app berbeda dengan isi mesin.
class SyncBanner extends StatelessWidget {
  const SyncBanner(this.m, {super.key});
  final MachineLink m;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final p = pal(context);
        if (m.pendingDecision) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: NeuBox(
              selected: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Setting di app berbeda dengan yang ada di mesin. Pilih mana yang dipakai:', style: TextStyle(color: p.text)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(
                    onPressed: () async {
                      final err = await m.resolveSend();
                      if (context.mounted) snack(context, err ?? 'Setting app dikirim dan tersimpan permanen di mesin');
                    },
                    child: const Text('Kirim ke mesin'),
                  ),
                  OutlinedButton(onPressed: m.resolvePull, child: const Text('Ambil dari mesin')),
                ]),
              ]),
            ),
          );
        }
        if (!m.needsSync) return const SizedBox.shrink();
        final online = m.isReady;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: NeuBox(
            child: Row(children: [
              const Icon(Icons.sync_problem, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(online ? 'Setting belum disinkron ke mesin' : 'Setting tersimpan di app, belum dikirim', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                  if (!online) Text(m.profile.deviceId == null ? 'Pasangkan ESP32 untuk sinkron' : 'Hubungkan mesin untuk sinkron', style: TextStyle(color: p.sub, fontSize: 12)),
                ]),
              ),
              if (online) FilledButton(onPressed: m.syncing ? null : () => doSync(context, m), child: Text(m.syncing ? '...' : 'SYNC')),
            ]),
          ),
        );
      },
    );
  }
}
