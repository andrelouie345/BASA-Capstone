import 'package:flutter/material.dart';

import '../models/learner.dart';
import 'status_badge.dart';

class LearnerProfilePanel extends StatelessWidget {
  const LearnerProfilePanel({
    super.key,
    required this.learner,
    required this.isExpanded,
    required this.onClose,
    required this.onToggleExpand,
  });

  final Learner learner;
  final bool isExpanded;
  final VoidCallback onClose;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final panelWidth = isExpanded ? 500.0 : 340.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: panelWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B234B).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE7EDF8), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'LEARNER PROFILE',
                    style: TextStyle(
                      color: Color(0xFF7D91B2),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Tooltip(
                  message: isExpanded ? 'Collapse profile' : 'Expand profile',
                  child: IconButton(
                    onPressed: onToggleExpand,
                    icon: Icon(
                      isExpanded ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
                      color: const Color(0xFF122C5B),
                      size: 18,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Close learner profile',
                  child: IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF122C5B)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF122C5B),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          learner.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    learner.name,
                    style: const TextStyle(
                      color: Color(0xFF122C5B),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${learner.grade} · ${learner.section} · Female',
                    style: const TextStyle(
                      color: Color(0xFF7D91B2),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    learner.lrn,
                    style: const TextStyle(
                      color: Color(0xFF7D91B2),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _buildSectionTitle('PERSONAL INFORMATION'),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow('Teacher', 'Mrs. A. R. Reyes'),
                        _buildInfoRow('Contact Person', 'Gloria Santos'),
                        _buildInfoRow('Contact No.', '09171000001'),
                        _buildInfoRow('Last Assessed', learner.lastAssessed),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _buildSectionTitle('ASSESSMENT RESULTS'),
                  const SizedBox(height: 10),
                  _buildAssessmentResult('CRLA Level', StatusBadge.crla(learner.crla)),
                  _buildAssessmentResult('Phil-IRI Level', StatusBadge.philIri(learner.philIri)),
                  _buildAssessmentResult('ARAL Status', StatusBadge.aralStatus(learner.aralStatus)),
                  const SizedBox(height: 22),
                  _buildSectionTitle('READING PROGRESS'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        _buildProgressRow('Pre-score', 34, '34%'),
                        const SizedBox(height: 12),
                        _buildProgressRow('Post-score', 48, '48%'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Reading Gain',
                                style: TextStyle(
                                  color: Color(0xFF7D91B2),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              learner.gain,
                              style: const TextStyle(
                                color: Color(0xFF1D8F5D),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _buildSectionTitle('ASSESSMENT HISTORY'),
                  const SizedBox(height: 10),
                  _buildHistoryItem('Phil-IRI', 'July 10, 2026', learner.philIri),
                  _buildHistoryItem('CRLA', 'July 10, 2026', learner.crla),
                  _buildHistoryItem('GST', 'July 5, 2026', 'Flagged'),
                  const SizedBox(height: 22),
                  _buildSectionTitle('ARAL PROGRAM'),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow('Status', learner.aralStatus),
                        _buildInfoRow('Intervention Level', 'Level 1'),
                        _buildInfoRow('Sessions Completed', '8 / 12'),
                        _buildInfoRow('Next Session', 'July 19, 2026'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF7D91B2),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF7D91B2),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF122C5B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssessmentResult(String label, Widget badge) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF7D91B2),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          badge,
        ],
      ),
    );
  }

  Widget _buildProgressRow(String label, int value, String percent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF7D91B2),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              percent,
              style: const TextStyle(
                color: Color(0xFF122C5B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value / 100,
            minHeight: 8,
            backgroundColor: const Color(0xFFE6EDF6),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1F67D6)),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryItem(String title, String date, String status) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1F67D6),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF122C5B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: const TextStyle(
                    color: Color(0xFF7D91B2),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  style: const TextStyle(
                    color: Color(0xFF122C5B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
