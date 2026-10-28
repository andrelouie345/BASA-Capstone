// lib/ui/auth/auth_backdrop.dart
// The page behind the sign-in screens: the background colour washed toward
// the primary and accent containers, with two soft glows. Theme colours only.
import 'package:flutter/material.dart';

class AuthBackdrop extends StatelessWidget {
  final Widget child;
  const AuthBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(colors.surface, colors.primaryContainer, 0.45)!,
            colors.surface,
            Color.lerp(colors.surface, colors.secondaryContainer, 0.30)!,
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -120, left: -80, child: _Glow(size: 320, color: colors.primary)),
          Positioned(bottom: -140, right: -100, child: _Glow(size: 360, color: colors.secondary)),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final double size;
  final Color color;
  const _Glow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)]),
      ),
    ),
  );
}
