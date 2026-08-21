import 'package:flutter/material.dart';

class BasaLogo extends StatelessWidget {
  const BasaLogo({
    super.key,
    this.size = 42,
    this.showLabel = false,
    this.labelColor = Colors.white,
  });

  final double size;
  final bool showLabel;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFF9A900), Color(0xFFFF8A3D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40F9A900),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.menu_book_rounded,
        color: Colors.white,
        size: 22,
      ),
    );

    if (!showLabel) {
      return logo;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(width: 12),
        Text(
          'BASA',
          style: TextStyle(
            color: labelColor,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
