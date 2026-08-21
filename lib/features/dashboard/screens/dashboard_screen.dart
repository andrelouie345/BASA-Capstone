import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../data/mock_auth_data.dart';
import '../../../data/mock_dashboard_data.dart';
import '../../learners/screens/learner_profiles_screen.dart';
import '../../assessments/screens/assessments_screen.dart';
import '../../aral/screens/aral_program_screen.dart';
import '../widgets/aral_session_card.dart';
import '../widgets/basa_sidebar.dart';
import '../widgets/dashboard_stat_card.dart';
import '../widgets/notification_menu.dart';
import '../widgets/reading_trend_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.initialRoute = '/dashboard'});

  final String initialRoute;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late String _activeRoute;
  final _searchController = TextEditingController();
  final _notifications = const [
    'Learner flagged for Phil-IRI assessment',
    'ARAL session scheduled',
    'New reading material available',
  ];

  MockUser get _user => MockAuthState.currentUser ?? defaultTeacherUser;

  @override
  void initState() {
    super.initState();
    _activeRoute = widget.initialRoute;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 980;

    return Scaffold(
      backgroundColor: const Color(0xFFEFF5FC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (isDesktop) {
              return Row(
                children: [
                  BasaSidebar(
                    activeRoute: _activeRoute,
                    user: _user,
                    onNavigate: (route) {
                      if (route == '/login?logout=1') {
                        _confirmLogout();
                        return;
                      }
                      setState(() => _activeRoute = route);
                      if (route != '/dashboard' &&
                          route != '/learners' &&
                          route != '/aral' &&
                          !route.startsWith('/assessments')) {
                        _showPlaceholderMessage(route);
                      }
                    },
                  ),
                  Expanded(child: _buildMainContent(context)),
                ],
              );
            }

            return _buildMobileScaffold();
          },
        ),
      ),
    );
  }

  Widget _buildMobileScaffold() {
    final user = _user;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('BASA'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: SizedBox(
        width: 260,
        child: BasaSidebar(
          activeRoute: _activeRoute,
          user: user,
          onNavigate: (route) {
            if (route == '/login?logout=1') {
              _confirmLogout();
              return;
            }
            setState(() => _activeRoute = route);
            if (route != '/dashboard' &&
                route != '/learners' &&
                route != '/aral' &&
                !route.startsWith('/assessments')) {
              _showPlaceholderMessage(route);
            }
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _buildMainContent(context, compact: true),
    );
  }

  Widget _buildMainContent(BuildContext context, {bool compact = false}) {
    final user = _user;

    if (_activeRoute == '/learners') {
      return Column(
        children: [
          _buildHeaderRow(
            context,
            compact: compact,
            breadcrumb: 'BASA > Learner Profiles',
            user: user,
          ),
          Expanded(child: const LearnerProfilesScreen()),
        ],
      );
    }

    if (_activeRoute.startsWith('/assessments')) {
      final tab = _activeRoute == '/assessments/phil-iri' ? 'Phil-IRI' : 'GST';
      return Column(
        children: [
          _buildHeaderRow(
            context,
            compact: compact,
            breadcrumb: 'BASA > Reading Assessments',
            user: user,
          ),
          Expanded(child: AssessmentsScreen(initialTab: tab)),
        ],
      );
    }

    if (_activeRoute == '/aral') {
      return Column(
        children: [
          _buildHeaderRow(
            context,
            compact: compact,
            breadcrumb: 'BASA > ARAL Program Management',
            user: user,
          ),
          const Expanded(child: AralProgramScreen()),
        ],
      );
    }

    return Column(
      children: [
        _buildHeaderRow(
          context,
          compact: compact,
          breadcrumb: 'BASA > Dashboard',
          user: user,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard',
                  style: TextStyle(
                    color: Color(0xFF122C5B),
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, inner) {
                    if (inner.maxWidth < 768) {
                      // Mobile: Stack vertically
                      return Column(
                        spacing: 14,
                        children: [
                          DashboardStatCard(
                            value: '${MockDashboardData.stats.learners}',
                            title: 'My Learners',
                            description: 'All enrolled learners',
                            icon: Icons.group_rounded,
                            backgroundColor: const Color(0xFF142D5B),
                            primaryColor: Colors.white,
                            iconBackgroundColor: const Color(0xFF1F3D7A),
                            onTap: () => _handleNavigation('/learners'),
                          ),
                          DashboardStatCard(
                            value: '${MockDashboardData.stats.flaggedPhilIri}',
                            title: 'Flagged for Phil-IRI',
                            description: 'Need individual assessment',
                            icon: Icons.warning_amber_rounded,
                            backgroundColor: const Color(0xFFFFF1F1),
                            primaryColor: const Color(0xFFD84C66),
                            iconBackgroundColor: Colors.white,
                            onTap: () =>
                                _handleNavigation('/assessments/phil-iri'),
                          ),
                          DashboardStatCard(
                            value: '${MockDashboardData.stats.todaysSessions}',
                            title: "Today's Sessions",
                            description: 'ARAL sessions scheduled',
                            icon: Icons.calendar_today_rounded,
                            backgroundColor: const Color(0xFFEEF5FF),
                            primaryColor: const Color(0xFF1F67D6),
                            iconBackgroundColor: Colors.white,
                            onTap: () => _handleNavigation('/aral'),
                          ),
                          DashboardStatCard(
                            value:
                                '${MockDashboardData.stats.materialsAvailable}',
                            title: 'Materials Available',
                            description: 'In the repository',
                            icon: Icons.menu_book_rounded,
                            backgroundColor: const Color(0xFFEDFBF5),
                            primaryColor: const Color(0xFF1D8F5D),
                            iconBackgroundColor: Colors.white,
                            onTap: () => _handleNavigation('/materials'),
                          ),
                        ],
                      );
                    } else {
                      // Desktop/Tablet: Row with 4 equal cards
                      return Row(
                        children: [
                          Expanded(
                            child: DashboardStatCard(
                              value: '${MockDashboardData.stats.learners}',
                              title: 'My Learners',
                              description: 'All enrolled learners',
                              icon: Icons.group_rounded,
                              backgroundColor: const Color(0xFF142D5B),
                              primaryColor: Colors.white,
                              iconBackgroundColor: const Color(0xFF1F3D7A),
                              onTap: () => _handleNavigation('/learners'),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: DashboardStatCard(
                              value:
                                  '${MockDashboardData.stats.flaggedPhilIri}',
                              title: 'Flagged for Phil-IRI',
                              description: 'Need individual assessment',
                              icon: Icons.warning_amber_rounded,
                              backgroundColor: const Color(0xFFFFF1F1),
                              primaryColor: const Color(0xFFD84C66),
                              iconBackgroundColor: Colors.white,
                              onTap: () =>
                                  _handleNavigation('/assessments/phil-iri'),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: DashboardStatCard(
                              value:
                                  '${MockDashboardData.stats.todaysSessions}',
                              title: "Today's Sessions",
                              description: 'ARAL sessions scheduled',
                              icon: Icons.calendar_today_rounded,
                              backgroundColor: const Color(0xFFEEF5FF),
                              primaryColor: const Color(0xFF1F67D6),
                              iconBackgroundColor: Colors.white,
                              onTap: () => _handleNavigation('/aral'),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: DashboardStatCard(
                              value:
                                  '${MockDashboardData.stats.materialsAvailable}',
                              title: 'Materials Available',
                              description: 'In the repository',
                              icon: Icons.menu_book_rounded,
                              backgroundColor: const Color(0xFFEDFBF5),
                              primaryColor: const Color(0xFF1D8F5D),
                              iconBackgroundColor: Colors.white,
                              onTap: () => _handleNavigation('/materials'),
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120B234B),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Teacher Workflow — Reading Assessment Tasks',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF122C5B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Quick access to each step of the assessment and intervention cycle',
                        style: TextStyle(
                          color: Color(0xFF6F7F9B),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, workflowConstraints) {
                          final columns = workflowConstraints.maxWidth >= 900
                              ? 3
                              : 1;
                          return GridView.count(
                            crossAxisCount: columns,
                            shrinkWrap: true,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: 1.15,
                            children: [
                              _buildWorkflowTile(
                                label: 'TASKS 1–2',
                                title: 'Administer GST',
                                description:
                                    'Enter raw scores for your class roster and classify At-Level vs Flagged.',
                                buttonLabel: 'Open GST >',
                                accent: const Color(0xFFF9A900),
                                icon: Icons.layers_rounded,
                                onTap: () =>
                                    _handleNavigation('/assessments/gst'),
                              ),
                              _buildWorkflowTile(
                                label: 'TASKS 3–7',
                                title: 'Individual Phil-IRI Session',
                                description:
                                    'Start a live oral reading session with miscues tracking and auto-classification.',
                                buttonLabel: 'Start Session >',
                                accent: const Color(0xFF8F6AE7),
                                icon: Icons.book_rounded,
                                onTap: () =>
                                    _handleNavigation('/assessments/phil-iri'),
                              ),
                              _buildWorkflowTile(
                                label: 'TASKS 8–9',
                                title: 'View Material Recommendations',
                                description:
                                    "Browse curated materials matched to each learner's reading profile.",
                                buttonLabel: 'Go to Materials >',
                                accent: const Color(0xFF23A77A),
                                icon: Icons.auto_stories_rounded,
                                onTap: () => _handleNavigation('/materials'),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4D9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEDC66D)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFB36500),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              '2 learners pending ARAL enrollment',
                              style: TextStyle(
                                color: Color(0xFF8B5B00),
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'These learners qualified via GST/CRLA but have not yet been enrolled in the reading intervention program.',
                              style: TextStyle(
                                color: Color(0xFF8B5B00),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _handleNavigation('/aral'),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFF9A900),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Enroll Now'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, bottomConstraints) {
                    final wide = bottomConstraints.maxWidth >= 900;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: wide ? 2 : 1,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x120B234B),
                                  blurRadius: 16,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Reading Level Trend',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Color(0xFF122C5B),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () => _showToast(
                                        'Reading trend exported successfully.',
                                      ),
                                      icon: const Icon(
                                        Icons.download_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Export'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Feb – Jul 2026 · All grades',
                                  style: TextStyle(
                                    color: Color(0xFF7D91B2),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ReadingTrendChart(
                                  data: MockDashboardData.readingTrend,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: wide ? 1 : 1,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x120B234B),
                                  blurRadius: 16,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        "Today's ARAL Sessions",
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Color(0xFF122C5B),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () =>
                                          _handleNavigation('/aral'),
                                      child: const Text('View >'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '4 sessions · July 19',
                                  style: TextStyle(
                                    color: Color(0xFF7D91B2),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...MockDashboardData.sessions.map((session) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: AralSessionCard(
                                      session: session,
                                      onTap: () => _showSessionDetails(session),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowTile({
    required String label,
    required String title,
    required String description,
    required String buttonLabel,
    required Color accent,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EEF8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: 0.08,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF122C5B),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF627699),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              buttonLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _handleNavigation(String route) {
    setState(() => _activeRoute = route);
    if (route == '/login?logout=1') return;
    if (route.startsWith('/') &&
        route != '/learners' &&
        route != '/aral' &&
        !route.startsWith('/assessments')) {
      _showPlaceholderMessage(route);
    }
  }

  void _showPlaceholderMessage(String route) {
    final routeName = route.replaceFirst('/', '').replaceAll('-', ' ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$routeName is under development.')));
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showNotifications(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (box == null || overlay == null) {
      return;
    }
    final position = box.localToGlobal(
      Offset.zero,
      ancestor: overlay as RenderObject?,
    );
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + 50,
        position.dx + 300,
        position.dy + 250,
      ),
      items: const [],
      constraints: const BoxConstraints(maxWidth: 320),
    );

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Notifications'),
        content: NotificationMenu(items: _notifications),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSessionDetails(AralSession session) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(session.learner),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Time: ${session.time}'),
            const SizedBox(height: 8),
            Text('Duration: ${session.duration}'),
            const SizedBox(height: 8),
            Text('Activity: ${session.activity}'),
            const SizedBox(height: 8),
            Text('Status: ${session.status}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context, {
    required bool compact,
    required String breadcrumb,
    required MockUser user,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              breadcrumb,
              style: const TextStyle(
                color: Color(0xFF7D91B2),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: compact ? 160 : 220,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                filled: true,
                fillColor: const Color(0xFFF5F8FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE3EAFE)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE3EAFE)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF122C5B),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Builder(
            builder: (context) {
              return Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    onPressed: () => _showNotifications(context),
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: Color(0xFF122C5B),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF9A900),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 10),
          Row(
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      color: Color(0xFF122C5B),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    user.role,
                    style: const TextStyle(
                      color: Color(0xFF7D91B2),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to sign out of BASA?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              MockAuthState.signOut();
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
