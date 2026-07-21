import 'package:flutter/material.dart';

/// BellaTV brand mark. Shows the app logo image (assets/images/app_logo.png),
/// used everywhere the app name would otherwise appear (app bars, login).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.24;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.22),
            blurRadius: size * 0.4,
            spreadRadius: -size * 0.12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/images/app_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          // If the asset ever fails to load, fall back to a neutral tile so
          // the app bar never shows a broken-image glyph.
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            color: const Color(0xFF112236),
          ),
        ),
      ),
    );
  }
}
