import 'package:flutter/material.dart';

class LearnerAvatar extends StatelessWidget {
  const LearnerAvatar({
    super.key,
    required this.initials,
  });

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF5FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF122C5B),
          ),
        ),
      ),
    );
  }
}
