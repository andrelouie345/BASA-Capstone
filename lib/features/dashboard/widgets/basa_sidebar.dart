import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/mock_auth_data.dart';
import '../../../shared/widgets/basa_logo.dart';

class BasaSidebar extends StatelessWidget {
  const BasaSidebar({
    super.key,
    required this.activeRoute,
    required this.onNavigate,
    required this.user,
  });

  final String activeRoute;
  final ValueChanged<String> onNavigate;
  final MockUser user;

  @override
  Widget build(BuildContext context) {
    final items = <_SidebarItemData>[
      _SidebarItemData('Dashboard', '/dashboard', Icons.grid_view_rounded),
      _SidebarItemData('Learners', '/learners', Icons.people_alt_rounded),
      _SidebarItemData('Assessments', '/assessments', Icons.assignment_rounded, badge: 'GST'),
      _SidebarItemData('ARAL Program', '/aral', Icons.calendar_month_rounded),
      _SidebarItemData('Analytics', '/analytics', Icons.bar_chart_rounded),
      _SidebarItemData('Materials', '/materials', Icons.menu_book_rounded, badge: '20'),
      _SidebarItemData('Settings', '/settings', Icons.settings_rounded),
    ];

    return Container(
      width: 270,
      color: BasaTheme.darkNavy,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            children: [
              Row(
                children: const [
                  BasaLogo(size: 34),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BASA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                      Text(
                        'READING SYSTEM',
                        style: TextStyle(
                          color: Color(0xFF9BB2D6),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.08,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16315F),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF294D82),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mapayapa Elementary School',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Div. Quezon City • S.Y. 2025–26',
                            style: TextStyle(
                              color: Color(0xFF9BB2D6),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF294D82),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Teacher Module',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    'MAIN MENU',
                    style: TextStyle(
                      color: const Color(0xFF8EA7CB),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...items.map((item) {
                final selected = item.route == activeRoute;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onNavigate(item.route),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF21477B) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            size: 18,
                            color: selected ? Colors.white : const Color(0xFF9BAFCC),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                color: selected ? Colors.white : const Color(0xFFB4C6E5),
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (item.badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: item.badge == 'GST' ? const Color(0xFF1C355F) : const Color(0xFF1C355F),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                item.badge!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF16315F),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF5FC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'AR',
                          style: TextStyle(
                            color: BasaTheme.darkNavy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.role,
                            style: const TextStyle(
                              color: Color(0xFFB4C6E5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => onNavigate('/login?logout=1'),
                      borderRadius: BorderRadius.circular(10),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.logout_rounded, color: Color(0xFFB4C6E5), size: 18),
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

class _SidebarItemData {
  const _SidebarItemData(
    this.label,
    this.route,
    this.icon, {
    this.badge,
  });

  final String label;
  final String route;
  final IconData icon;
  final String? badge;
}
