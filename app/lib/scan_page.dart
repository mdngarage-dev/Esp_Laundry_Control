import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'ui_helpers.dart';

/// Scan barcode nomor order (struk laundry). Mengembalikan teks barcode, atau null jika dibatalkan.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController ctl = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool done = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _finish(String v) {
    if (done) return;
    done = true;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan barcode order')),
      body: Column(children: [
        Expanded(
          child: MobileScanner(
            controller: ctl,
            onDetect: (capture) {
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  _finish(v);
                  return;
                }
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Text('Arahkan kamera ke barcode di struk.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.keyboard),
              label: const Text('Ketik nomor order manual'),
              onPressed: () async {
                final t = await askText(context, 'Nomor order', '', number: false);
                if (t != null && t.isNotEmpty) _finish(t);
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
