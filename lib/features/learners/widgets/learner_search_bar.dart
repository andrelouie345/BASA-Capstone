import 'package:flutter/material.dart';

class LearnerSearchBar extends StatelessWidget {
  const LearnerSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 450,
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search by name or LRN...',
          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF7D91B2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          filled: true,
          fillColor: const Color(0xFFF5F8FC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE3EAFE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE3EAFE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF122C5B), width: 1.5),
          ),
          hintStyle: const TextStyle(
            fontSize: 14,
            color: Color(0xFFADB8CC),
          ),
        ),
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF122C5B),
        ),
      ),
    );
  }
}
