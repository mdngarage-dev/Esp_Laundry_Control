import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// ======================= COCOKKAN DENGAN APLIKASI LAUNDRY LAMA (sudah dicek dari order_detail.dart) =======================
const String kOrderCollection = 'order';
const String kFieldCode = 'nomor_pelanggan';   // nomor order (isi QR)
const String kFieldName = 'nama_pelanggan';
const String kFieldStatus = 'status';
const String kStatusQueued = 'antrian';        // status sebelum mesin mulai
const String kStatusProcessing = 'proses';     // sama dengan tombol "Mulai Proses" di aplikasi lama (hanya field status)
/// Field tambahan yang ikut ditulis. Tombol "Mulai Proses" lama hanya menulis status, jadi kosong.
/// Jika diisi, aturan Firestore (docs/firestore.rules) harus ikut diubah (hasOnly([...])).
Map<String, Object?> processingExtraFields() => <String, Object?>{};
// =====================================================================================================================

class OrderInfo {
  OrderInfo(this.docId, this.code, this.name, this.status);
  final String docId, code, name, status;
}

/// Jembatan ke Firestore laundry TANPA login: cari nama pelanggan dari nomor order, dan ubah status
/// antrian -> proses saat mesin mulai. Semua gagal dengan aman (aplikasi tetap bisa mengontrol mesin tanpa Firebase).
class OrderService extends ChangeNotifier {
  bool ready = false;          // Firebase berhasil diinisialisasi
  String? initError, lastError;
  bool writeStatus = false;    // ubah status di Firestore saat mesin mulai (default mati)
  final List<String> pending = []; // nomor order yang statusnya belum berhasil diubah (offline / ditolak)
  Timer? _timer;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    writeStatus = p.getBool('order_write_status') ?? false;
    pending.addAll(p.getStringList('order_pending') ?? const []);
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      ready = true;
    } catch (e) {
      initError = '$e';
    }
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => flushPending());
    flushPending();
  }

  Future<void> setWriteStatus(bool v) async {
    writeStatus = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('order_write_status', v);
  }

  /// ID dokumen di aplikasi laundry acak, jadi pencarian utama lewat field nomor_pelanggan (butuh izin baca/list
  /// di aturan Firestore). Cadangan: jika suatu saat ID dokumen = nomor order, ambil langsung lewat ID.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _find(String code) async {
    final col = FirebaseFirestore.instance.collection(kOrderCollection);
    try {
      final q = await col.where(kFieldCode, isEqualTo: code).limit(1).get().timeout(const Duration(seconds: 8));
      if (q.docs.isNotEmpty) return q.docs.first;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    try {
      final d = await col.doc(code).get().timeout(const Duration(seconds: 8));
      if (d.exists) return d;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    return null;
  }

  /// Nama pelanggan dari nomor order. Null jika offline / belum dikonfigurasi / order tidak ada.
  Future<OrderInfo?> lookup(String code) async {
    lastError = null;
    if (!ready) {
      lastError = 'Firebase belum dikonfigurasi';
      return null;
    }
    try {
      final d = await _find(code);
      if (d == null) {
        lastError = 'Order $code tidak ditemukan (atau ID dokumen bukan nomor order / ditolak aturan Firestore)';
        return null;
      }
      final m = d.data() ?? {};
      return OrderInfo(d.id, code, (m[kFieldName] ?? '').toString(), (m[kFieldStatus] ?? '').toString());
    } catch (e) {
      lastError = 'Gagal membaca Firestore: $e';
      return null;
    }
  }

  /// Ubah status antrian -> proses HANYA jika status sekarang masih antrian (transaksi), sehingga mesin kedua
  /// (mis. dryer setelah mesin cuci) tidak menimpa status yang sudah berjalan. Mengembalikan pesan hasil.
  Future<String> markProcessing(String code) async {
    if (!writeStatus) return 'Update status Firestore nonaktif';
    if (!ready) return _queue(code, 'Firebase belum dikonfigurasi');
    try {
      final d = await _find(code);
      if (d == null) return 'Order $code tidak ditemukan di Firestore';
      String result = '';
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(d.reference);
        final st = ((snap.data() ?? {})[kFieldStatus] ?? '').toString().toLowerCase();
        if (st == kStatusQueued) {
          tx.update(d.reference, <String, Object?>{kFieldStatus: kStatusProcessing, ...processingExtraFields()});
          result = 'Order $code: status diubah ke "$kStatusProcessing"';
        } else {
          result = 'Order $code: status sudah "$st", tidak diubah';
        }
      }).timeout(const Duration(seconds: 12));
      pending.remove(code);
      await _savePending();
      return result;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        pending.remove(code); // ditolak aturan: jangan diulang terus
        await _savePending();
        return 'Order $code: DITOLAK aturan Firestore (periksa docs/firestore.rules sudah dipublikasikan)';
      }
      return _queue(code, 'Gagal menulis Firestore (${e.code})');
    } catch (e) {
      return _queue(code, 'Gagal menulis Firestore ($e)');
    }
  }

  String _queue(String code, String why) {
    if (!pending.contains(code)) pending.add(code);
    _savePending();
    notifyListeners();
    return 'Order $code: $why. Akan dicoba lagi otomatis.';
  }

  Future<void> _savePending() async => (await SharedPreferences.getInstance()).setStringList('order_pending', pending);

  Future<void> flushPending() async {
    if (!ready || !writeStatus || pending.isEmpty) return;
    for (final c in List<String>.of(pending)) {
      await markProcessing(c);
    }
    notifyListeners();
  }
}

final OrderService orders = OrderService();
