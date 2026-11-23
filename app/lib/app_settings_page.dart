import 'package:flutter/material.dart';

import 'order_settings_page.dart';
import 'theme.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tampilan aplikasi')),
      body: ListenableBuilder(
        listenable: appSettings,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          NeuBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tema'),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Terang'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Gelap'), icon: Icon(Icons.dark_mode)),
                  ButtonSegment(value: ThemeMode.system, label: Text('Ikut HP'), icon: Icon(Icons.phone_android)),
                ],
                selected: {appSettings.mode},
                onSelectionChanged: (s) => appSettings.setMode(s.first),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          NeuBox(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Efek animasi saat mesin bekerja'),
              subtitle: const Text('Air dan gelembung (mesin cuci), gelombang panas (dryer). Matikan jika HP terasa berat.'),
              value: appSettings.effects,
              onChanged: appSettings.setEffects,
            ),
          ),
          const SizedBox(height: 16),
          NeuBox(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderSettingsPage())),
            child: const Row(children: [Icon(Icons.cloud_sync), SizedBox(width: 14), Expanded(child: Text('Order & Firebase (nama pelanggan, status order)')), Icon(Icons.chevron_right)]),
          ),
        ]),
      ),
    );
  }
}
