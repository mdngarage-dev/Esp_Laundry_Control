import 'package:flutter/material.dart';

import 'history.dart';
import 'machine_list_page.dart';
import 'order_service.dart';
import 'store.dart';
import 'theme.dart';
import 'ui_helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appSettings.load();
  await orderLog.load();
  await store.load();
  orders.init(); // Firebase (boleh gagal: aplikasi tetap jalan tanpa fitur nama pelanggan)
  runApp(const DryerApp());
  store.connectAll(); // sambungkan semua mesin tersimpan di latar belakang
}

class DryerApp extends StatelessWidget {
  const DryerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) => MaterialApp(
        title: 'Mesin Saya',
        scaffoldMessengerKey: messengerKey,
        themeMode: appSettings.mode,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const MachineListPage(),
      ),
    );
  }
}
