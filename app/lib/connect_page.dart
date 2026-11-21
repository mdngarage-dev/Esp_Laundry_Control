import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dryer_link.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final pinCtl = TextEditingController(text: '123456');

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final s = p.getString('pin');
      if (s != null && mounted) pinCtl.text = s;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (link.phase == LinkPhase.idle) link.autoConnect();
    });
  }

  @override
  void dispose() {
    pinCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hubungkan ke mesin dryer')),
      body: ListenableBuilder(
        listenable: link,
        builder: (context, _) {
          final busy = link.phase == LinkPhase.scanning || link.phase == LinkPhase.connecting || link.phase == LinkPhase.authing;
          return ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              controller: pinCtl,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'PIN mesin (default 123456)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : link.startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(link.phase == LinkPhase.scanning ? 'Mencari...' : 'Cari mesin'),
            ),
            if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
            if (link.phase == LinkPhase.connecting) const Text('Menghubungkan...'),
            if (link.phase == LinkPhase.authing) const Text('Verifikasi PIN...'),
            if (link.lastError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(link.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            for (final r in link.results)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.local_laundry_service),
                  title: Text(r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName),
                  subtitle: Text('${r.device.remoteId.str}   RSSI ${r.rssi}'),
                  onTap: busy ? null : () => link.connect(r.device, pinCtl.text.trim()),
                ),
              ),
            if (link.results.isEmpty && !busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Tidak ada mesin ditemukan. Pastikan mesin menyala dan Bluetooth + izin "Perangkat sekitar" aktif.'),
              ),
          ]);
        },
      ),
    );
  }
}
