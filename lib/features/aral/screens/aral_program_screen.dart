import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class AralProgramScreen extends StatefulWidget {
  const AralProgramScreen({super.key});

  @override
  State<AralProgramScreen> createState() => _AralProgramScreenState();
}

class _AralProgramScreenState extends State<AralProgramScreen> {
  final List<_AralLearner> _learners = [
    _AralLearner(
      'Ana Marie Lim',
      '103402210031',
      'Grade 4',
      'Ilang-Ilang',
      'Non-Reader',
      'Frustration',
      'Active',
      'Non-Reader (CRLA)',
      0xFFE8A8B7,
    ),
    _AralLearner(
      'Miguel Antonio Torres',
      '103402210110',
      'Grade 3',
      'Sampaguita',
      'Non-Reader',
      'Frustration',
      'Active',
      'Non-Reader (CRLA)',
      0xFFAFC8EE,
    ),
    _AralLearner(
      'Roberto Juan Dizon',
      '103402210133',
      'Grade 3',
      'Sampaguita',
      'Non-Reader',
      'Frustration',
      'Pending',
      'Non-Reader (CRLA)',
      0xFFD8B8E7,
    ),
    _AralLearner(
      'Andres Bonifacio Tan',
      '103402210205',
      'Grade 2',
      'Rosal',
      'Non-Reader',
      'Frustration',
      'Active',
      'Non-Reader (CRLA)',
      0xFFF0C58B,
    ),
    _AralLearner(
      'Maria Elena Santos',
      '103402210012',
      'Grade 3',
      'Sampaguita',
      'Low',
      'Frustration',
      'Active',
      'Low Level (CRLA)',
      0xFFA9D8CC,
    ),
    _AralLearner(
      'Luz Divina Garcia',
      '103402210057',
      'Grade 2',
      'Rosal',
      'Low',
      'Frustration',
      'Pending',
      'Low Level (CRLA)',
      0xFFF0B5A2,
    ),
  ];

  String _activeTab = 'Identification';
  final int _completedPrograms = 2;

  int get _activeCount =>
      10 + _learners.where((learner) => learner.status == 'Active').length - 4;
  int get _pendingCount =>
      2 + _learners.where((learner) => learner.status == 'Pending').length - 2;

  void _enroll(_AralLearner learner) {
    setState(() => learner.status = 'Active');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${learner.name} enrolled in ARAL.')),
    );
  }

  void _exportLearners() {
    final csv = [
      'Learner,LRN,Grade,Section,CRLA,Phil-IRI,ARAL Status',
      ..._learners.map(
        (learner) =>
            '${learner.name},${learner.lrn},${learner.grade},${learner.section},${learner.crla},${learner.philIri},${learner.status}',
      ),
    ].join('\n');
    debugPrint(csv);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ARAL learner list exported successfully.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTabs(),
          const SizedBox(height: 20),
          if (_activeTab == 'Identification')
            _buildIdentification()
          else
            _buildComingSoon(),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BasaTheme.cardBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ['Identification', 'Planning', 'Schedule', 'Monitoring']
              .map((tab) {
                final selected = tab == _activeTab;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _activeTab = tab),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? BasaTheme.primaryNavy
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tab,
                        style: TextStyle(
                          color: selected ? Colors.white : BasaTheme.mutedText,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(),
        ),
      ),
    );
  }

  Widget _buildIdentification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 4
                : (constraints.maxWidth >= 600 ? 2 : 1);
            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: columns == 1 ? 3.2 : 1.55,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _summaryCard(
                  '$_qualifyingCount',
                  'Qualify for ARAL',
                  'Non-Reader or Low / Frustration',
                  Icons.flag_rounded,
                  const Color(0xFFD84C66),
                  const Color(0xFFFFF1F1),
                ),
                _summaryCard(
                  '$_activeCount',
                  'Currently Active',
                  'Enrolled and receiving intervention',
                  Icons.groups_rounded,
                  const Color(0xFF236BCB),
                  const Color(0xFFEEF5FF),
                ),
                _summaryCard(
                  '$_pendingCount',
                  'Pending Enrollment',
                  'Qualified but not yet enrolled',
                  Icons.schedule_rounded,
                  const Color(0xFFE8912B),
                  const Color(0xFFFFF4E6),
                ),
                _summaryCard(
                  '$_completedPrograms',
                  'Completed Program',
                  'Exited with improved reading level',
                  Icons.check_circle_rounded,
                  const Color(0xFF1D8F5D),
                  const Color(0xFFEDFBF5),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        _buildLearnersCard(),
      ],
    );
  }

  int get _qualifyingCount => 10;

  Widget _summaryCard(
    String value,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    Color iconBackground,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100B234B),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 27,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: BasaTheme.darkNavy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BasaTheme.mutedText,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLearnersCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100B234B),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Learners Qualifying for ARAL',
                      style: TextStyle(
                        color: BasaTheme.darkNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Based on CRLA and Phil-IRI results — sorted by urgency',
                      style: TextStyle(
                        color: BasaTheme.mutedText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _exportLearners,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Export'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BasaTheme.primaryNavy,
                  side: const BorderSide(color: BasaTheme.cardBorder),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return Column(
                  children: _learners.map(_buildLearnerMobileCard).toList(),
                );
              }
              return _buildDesktopTable();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(color: BasaTheme.softGray),
          child: const Row(
            children: [
              Expanded(flex: 28, child: _TableHeading('LEARNER')),
              Expanded(flex: 16, child: _TableHeading('GRADE / SECTION')),
              Expanded(flex: 13, child: _TableHeading('CRLA')),
              Expanded(flex: 13, child: _TableHeading('PHIL-IRI')),
              Expanded(flex: 17, child: _TableHeading('BASIS')),
              Expanded(flex: 13, child: _TableHeading('ARAL STATUS')),
              SizedBox(width: 82, child: _TableHeading('ACTION')),
            ],
          ),
        ),
        ..._learners.map(_buildDesktopRow),
      ],
    );
  }

  Widget _buildDesktopRow(_AralLearner learner) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BasaTheme.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(flex: 28, child: _learnerIdentity(learner)),
          Expanded(flex: 16, child: _gradeSection(learner)),
          Expanded(
            flex: 13,
            child: _classificationBadge(
              learner.crla,
              learner.crla == 'Non-Reader'
                  ? const Color(0xFFD84C66)
                  : const Color(0xFFE8912B),
            ),
          ),
          Expanded(
            flex: 13,
            child: _classificationBadge(
              learner.philIri,
              const Color(0xFFD84C66),
            ),
          ),
          Expanded(flex: 17, child: _basisBadge(learner.basis)),
          Expanded(flex: 13, child: _statusBadge(learner.status)),
          SizedBox(width: 82, child: _action(learner)),
        ],
      ),
    );
  }

  Widget _buildLearnerMobileCard(_AralLearner learner) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BasaTheme.softGray,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BasaTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _learnerIdentity(learner)),
              _statusBadge(learner.status),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _gradeSection(learner),
              _classificationBadge(
                learner.crla,
                learner.crla == 'Non-Reader'
                    ? const Color(0xFFD84C66)
                    : const Color(0xFFE8912B),
              ),
              _classificationBadge(learner.philIri, const Color(0xFFD84C66)),
              _basisBadge(learner.basis),
            ],
          ),
          if (learner.status == 'Pending') ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: _action(learner)),
          ],
        ],
      ),
    );
  }

  Widget _learnerIdentity(_AralLearner learner) {
    return Row(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: Color(learner.avatarColor),
          child: Text(
            _initials(learner.name),
            style: const TextStyle(
              color: BasaTheme.darkNavy,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                learner.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BasaTheme.darkNavy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                learner.lrn,
                style: const TextStyle(
                  color: BasaTheme.mutedText,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _initials(String name) =>
      name.split(' ').take(2).map((part) => part[0]).join();

  Widget _gradeSection(_AralLearner learner) {
    return Text(
      '${learner.grade} • ${learner.section}',
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: BasaTheme.slate,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _classificationBadge(String text, Color color) {
    return _pill(
      text,
      color.withValues(alpha: 0.11),
      color,
      border: color.withValues(alpha: 0.23),
    );
  }

  Widget _basisBadge(String text) => _pill(
    text,
    BasaTheme.softGray,
    BasaTheme.slate,
    border: BasaTheme.cardBorder,
  );

  Widget _statusBadge(String status) {
    final color = status == 'Active'
        ? const Color(0xFF236BCB)
        : const Color(0xFFE8912B);
    return _pill(
      status,
      color.withValues(alpha: 0.11),
      color,
      border: color.withValues(alpha: 0.22),
    );
  }

  Widget _pill(
    String text,
    Color background,
    Color foreground, {
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _action(_AralLearner learner) {
    if (learner.status == 'Active') {
      return const Text(
        'Enrolled',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: BasaTheme.mutedText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: () => _enroll(learner),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
        label: const Text(
          'Enroll',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }

  Widget _buildComingSoon() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100B234B),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.construction_rounded,
            color: BasaTheme.mutedText,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            '$_activeTab workspace',
            style: const TextStyle(
              color: BasaTheme.darkNavy,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'This ARAL workspace is ready for the next frontend phase.',
            style: TextStyle(color: BasaTheme.mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TableHeading extends StatelessWidget {
  const _TableHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: BasaTheme.mutedText,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
    ),
  );
}

class _AralLearner {
  _AralLearner(
    this.name,
    this.lrn,
    this.grade,
    this.section,
    this.crla,
    this.philIri,
    this.status,
    this.basis,
    this.avatarColor,
  );

  final String name;
  final String lrn;
  final String grade;
  final String section;
  final String crla;
  final String philIri;
  String status;
  final String basis;
  final int avatarColor;
}
