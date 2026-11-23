import 'package:flutter/material.dart';

String fmtTime(int sec) {
  final h = sec ~/ 3600, m = (sec ~/ 60) % 60, s = sec % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String errText(String code) {
  switch (code) {
    case 'busy': return 'Ditolak: mesin sedang berjalan (setting hanya saat mesin berhenti)';
    case 'range': return 'Nilai di luar batas';
    case 'constraint': return 'Melanggar batas aman (tCut harus ≤ t_hard − 5 dan tCut − hyst ≥ 30)';
    case 'auth': return 'Belum login PIN';
    case 'pin': return 'PIN salah';
    case 'locked': return 'Terkunci 60 detik karena PIN salah berulang';
    case 'remote_start_off': return 'Mulai dari HP belum diaktifkan (Pengaturan)';
    case 'not_selected': return 'Pilih program dulu';
    case 'door_or_sensor': return 'Pintu terbuka atau sensor suhu bermasalah';
    case 'state': return 'Perintah tidak sesuai kondisi mesin';
    case 'state_or_door': return 'Tidak bisa lanjut: cek kondisi mesin dan pintu';
    case 'sensor': return 'Sensor suhu rusak / tidak terbaca';
    case 'flash': return 'Gagal menulis ke flash mesin';
    case 'timeout': return 'Tidak ada balasan dari mesin';
    case 'arg': return 'Argumen perintah salah';
    case 'terputus': return 'Koneksi ke mesin terputus';
    case 'order_required': return 'Scan barcode order dulu';
    case 'motor_or_plan': return 'Motor belum dipelajari / program tidak valid';
    case 'not_learned': return 'Jalankan Pelajari motor dulu';
    default: return code;
  }
}

String faultText(int c) => c == 1 ? 'Sensor suhu rusak' : c == 2 ? 'Suhu terlalu panas' : 'Api tidak menyala';

String washerFaultText(int c) {
  switch (c) {
    case 1: return 'Pintu tidak terkunci';
    case 4: return 'Beban tidak seimbang';
    case 5: return 'Air tidak masuk';
    case 6: return 'Air tidak keluar';
    case 7: return 'Motor macet / Hall bermasalah';
    case 8: return 'Motor belum dipelajari';
    case 9: return 'Driver motor trip berulang';
    default: return 'Error';
  }
}

void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<bool> confirm(BuildContext c, String title, String body, {String ok = 'Ya'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(BuildContext c, String title, String initial, {bool decimal = false, bool number = true}) async {
  final ctl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: number ? TextInputType.numberWithOptions(decimal: decimal, signed: true) : TextInputType.text,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
  ctl.dispose();
  return r;
}

/// Dipakai untuk menampilkan peringatan global (selesai / pintu terbuka / error) dari mesin mana pun.
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
