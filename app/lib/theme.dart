import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan tampilan aplikasi (tema terang/gelap + efek animasi), disimpan di HP.
class AppSettings extends ChangeNotifier {
  ThemeMode mode = ThemeMode.dark;
  bool effects = true;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode = ThemeMode.values[(p.getInt('themeMode') ?? 2).clamp(0, 2)];
    effects = p.getBool('effects') ?? true;
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('themeMode', m.index);
  }

  Future<void> setEffects(bool v) async {
    effects = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('effects', v);
  }

  /// Tombol cepat terang <-> gelap.
  void toggle(BuildContext c) =>
      setMode(Theme.of(c).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}

final AppSettings appSettings = AppSettings();

class Pal {
  const Pal(this.bg, this.hi, this.lo, this.text, this.sub, this.accent);
  final Color bg, hi, lo, text, sub, accent;
}

const Pal _light = Pal(Color(0xFFE6EBF2), Color(0xFFFFFFFF), Color(0xFFB4BDCC), Color(0xFF2B3340), Color(0xFF6B7587), Color(0xFFFF6B3D));
const Pal _dark = Pal(Color(0xFF1E2327), Color(0xFF2B323A), Color(0xFF12161A), Color(0xFFE8ECF0), Color(0xFF9AA4AF), Color(0xFFFF7A4D));

Pal pal(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? _dark : _light;
Color alpha(Color c, double o) => c.withAlpha((o.clamp(0.0, 1.0) * 255).round());

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? _dark : _light;
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Pastrami',
    brightness: b,
    colorSchemeSeed: p.accent,
    scaffoldBackgroundColor: p.bg,
    appBarTheme: AppBarTheme(backgroundColor: p.bg, foregroundColor: p.text, elevation: 0, scrolledUnderElevation: 0, centerTitle: true),
  );
}

/// Kotak neumorphic (timbul lembut). selected = bingkai warna aksen.
class NeuBox extends StatelessWidget {
  const NeuBox({super.key, this.child, this.radius = 22, this.padding = const EdgeInsets.all(14), this.onTap,
      this.circle = false, this.selected = false, this.depth = 1.0, this.width, this.height});
  final Widget? child;
  final double radius, depth;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool circle, selected;
  final double? width, height;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final box = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: p.bg,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: selected ? Border.all(color: p.accent, width: 2) : null,
        boxShadow: [
          BoxShadow(color: p.lo, offset: Offset(5 * depth, 5 * depth), blurRadius: 12 * depth),
          BoxShadow(color: p.hi, offset: Offset(-5 * depth, -5 * depth), blurRadius: 12 * depth),
        ],
      ),
      child: child,
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
  }
}

class NeuButton extends StatelessWidget {
  const NeuButton({super.key, required this.icon, required this.label, this.onTap, this.onLongPress, this.color});
  final IconData icon;
  final String label;
  final VoidCallback? onTap, onLongPress;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final on = onTap != null || onLongPress != null;
    return Opacity(
      opacity: on ? 1 : 0.4,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: NeuBox(
          radius: 18,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color ?? p.accent),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: p.text, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Tombol ikon terang/gelap untuk AppBar.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Terang / gelap',
        icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
        onPressed: () => appSettings.toggle(context),
      );
}
