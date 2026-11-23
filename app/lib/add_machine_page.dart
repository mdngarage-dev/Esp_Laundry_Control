import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'schema.dart';
import 'machine_link.dart';
import 'store.dart';
import 'ui_helpers.dart';

/// Daftar ESP32 hasil scan. onPick dipanggil saat salah satu diketuk.
class ScanList extends StatelessWidget {
  const ScanList({super.key, required this.onPick, this.disabled = false});
  final Future<void> Function(ScanResult r) onPick;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton.icon(
            onPressed: (store.scanning || disabled) ? null : store.scan,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(store.scanning ? 'Mencari...' : 'Cari ESP32'),
          ),
          if (store.scanning) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          if (store.scanError != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(store.scanError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          for (final r in store.scanResults)
            Card(
              child: ListTile(
                leading: const Icon(Icons.memory),
                title: Text(r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName),
                subtitle: Text('${r.device.remoteId.str}   RSSI ${r.rssi}'),
                onTap: disabled ? null : () => onPick(r),
              ),
            ),
          if (store.scanResults.isEmpty && !store.scanning)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Belum ada ESP32 ditemukan. Pastikan mesin menyala, Bluetooth aktif, dan izin "Perangkat sekitar" diberikan.'),
            ),
        ]);
      },
    );
  }
}

class AddMachinePage extends StatefulWidget {
  const AddMachinePage({super.key});
  @override
  State<AddMachinePage> createState() => _AddMachinePageState();
}

class _AddMachinePageState extends State<AddMachinePage> {
  String type = 'dryer';
  late final TextEditingController nameCtl;
  bool nameTouched = false, binding = false;

  String _defaultName(String t) => '${t == 'dryer' ? 'Dryer' : 'Mesin Cuci'} ${store.byType(t).length + 1}';

  @override
  void initState() {
    super.initState();
    nameCtl = TextEditingController(text: _defaultName(type));
  }

  @override
  void dispose() {
    nameCtl.dispose();
    super.dispose();
  }

  String? _validName() {
    final err = nameError(nameCtl.text);
    if (err != null) snack(context, err);
    return err == null ? normName(nameCtl.text) : null;
  }

  Future<void> _addOffline() async {
    final n = _validName();
    if (n == null) return;
    store.addOffline(type, n);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _bind(ScanResult r) async {
    final n = _validName();
    if (n == null) return;
    final pin = await askText(context, 'PIN mesin', '123456');
    if (pin == null || !mounted) return;
    setState(() => binding = true);
    final err = await store.addAndBind(type, n, r.device, pin);
    if (!mounted) return;
    setState(() => binding = false);
    if (err != null) {
      snack(context, err);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah mesin')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Kategori'),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'dryer', label: Text('Dryer'), icon: Icon(Icons.air)),
            ButtonSegment(value: 'washer', label: Text('Mesin cuci'), icon: Icon(Icons.local_laundry_service)),
          ],
          selected: {type},
          onSelectionChanged: (s) => setState(() {
            type = s.first;
            if (!nameTouched) nameCtl.text = _defaultName(type);
          }),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: nameCtl,
          onChanged: (_) => nameTouched = true,
          decoration: const InputDecoration(labelText: 'Nama mesin (mis. Mesin 1 bawah)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: binding ? null : _addOffline,
          icon: const Icon(Icons.save_alt),
          label: const Text('Simpan tanpa ESP32 (atur setting dulu, hubungkan nanti)'),
        ),
        const Divider(height: 32),
        OutlinedButton.icon(
          onPressed: binding
              ? null
              : () {
                  final n = _validName();
                  if (n == null) return;
                  store.addDemo(type, n);
                  Navigator.pop(context);
                },
          icon: const Icon(Icons.science),
          label: const Text('Tambah mesin DEMO (simulasi, tanpa ESP32)'),
        ),
        const Divider(height: 32),
        const Text('Atau hubungkan ESP32 sekarang'),
        const SizedBox(height: 8),
        if (binding) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        ScanList(onPick: _bind, disabled: binding),
      ]),
    );
  }
}

/// Pasangkan ESP32 ke mesin yang sudah dibuat offline.
class PairPage extends StatefulWidget {
  const PairPage(this.m, {super.key});
  final MachineLink m;
  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  bool binding = false;

  Future<void> _pick(ScanResult r) async {
    final pin = await askText(context, 'PIN mesin', '123456');
    if (pin == null || !mounted) return;
    setState(() => binding = true);
    final err = await store.bindExisting(widget.m, r.device, pin);
    if (!mounted) return;
    setState(() => binding = false);
    if (err != null) {
      snack(context, err);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pasangkan ESP32: ${widget.m.profile.name}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Setting yang sudah diatur offline akan ditawarkan untuk dikirim ke mesin setelah terhubung.'),
        const SizedBox(height: 12),
        if (binding) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        ScanList(onPick: _pick, disabled: binding),
      ]),
    );
  }
}
