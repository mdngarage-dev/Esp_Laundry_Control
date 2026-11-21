import 'package:flutter/material.dart';

import 'machine_list_page.dart';
import 'store.dart';
import 'ui_helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  runApp(const DryerApp());
  store.connectAll(); // sambungkan semua mesin tersimpan di latar belakang
}

class DryerApp extends StatelessWidget {
  const DryerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mesin Saya',
      scaffoldMessengerKey: messengerKey,
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true, brightness: Brightness.dark),
      home: const MachineListPage(),
    );
  }
}
