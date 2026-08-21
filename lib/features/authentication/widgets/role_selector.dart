import 'package:flutter/material.dart';

import '../models/user_role.dart';

class RoleSelector extends StatelessWidget {
  const RoleSelector({
    super.key,
    required this.selectedRole,
    required this.onChanged,
  });

  final UserRole selectedRole;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SIGN IN AS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF7D91B2),
            letterSpacing: 0.08,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: RoleCard(
                title: UserRole.teacher.label,
                icon: Icons.school_rounded,
                selected: selectedRole == UserRole.teacher,
                onTap: () => onChanged(UserRole.teacher),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RoleCard(
                title: UserRole.coordinator.label,
                icon: Icons.description_rounded,
                selected: selectedRole == UserRole.coordinator,
                onTap: () => onChanged(UserRole.coordinator),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RoleCard(
                title: UserRole.admin.label,
                icon: Icons.shield_rounded,
                selected: selectedRole == UserRole.admin,
                onTap: () => onChanged(UserRole.admin),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class RoleCard extends StatefulWidget {
  const RoleCard({
    super.key,
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<RoleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.selected ? const Color(0xFF122C5B) : const Color(0xFFE5ECF6);
    final iconColor = widget.selected ? const Color(0xFF122C5B) : const Color(0xFF7D91B2);
    final titleColor = widget.selected ? const Color(0xFF122C5B) : const Color(0xFF43557A);
    final backgroundColor = widget.selected ? const Color(0xFFEAF1FB) : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          height: 88,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: _hovered || widget.selected
                ? [
                    BoxShadow(
                      color: const Color(0x140B234B),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Stack(
            children: [
              Positioned(
                right: 8,
                bottom: 8,
                child: AnimatedOpacity(
                  opacity: widget.selected ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Color(0xFF122C5B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 12),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: iconColor, size: 22),
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
