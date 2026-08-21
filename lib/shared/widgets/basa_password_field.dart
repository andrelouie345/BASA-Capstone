import 'package:flutter/material.dart';

class BasaPasswordField extends StatefulWidget {
  const BasaPasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;

  @override
  State<BasaPasswordField> createState() => _BasaPasswordFieldState();
}

class _BasaPasswordFieldState extends State<BasaPasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4E5F7D),
            letterSpacing: 0.06,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          obscureText: _obscureText,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          validator: widget.validator,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
            prefixIconColor: const Color(0xFF8598B6),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscureText = !_obscureText),
              icon: Icon(
                _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: const Color(0xFF8598B6),
              ),
              tooltip: _obscureText ? 'Show password' : 'Hide password',
            ),
          ),
          style: const TextStyle(fontSize: 15, color: Color(0xFF122C5B)),
        ),
      ],
    );
  }
}
