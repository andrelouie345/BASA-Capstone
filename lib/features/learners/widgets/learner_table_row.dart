import 'package:flutter/material.dart';
import '../models/learner.dart';
import 'learner_avatar.dart';
import 'status_badge.dart';

class LearnerTableRow extends StatelessWidget {
  const LearnerTableRow({
    super.key,
    required this.learner,
    required this.onView,
    this.isSelected = false,
  });

  final Learner learner;
  final VoidCallback onView;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEEF5FF) : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF000000).withValues(alpha: 0.05),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  LearnerAvatar(initials: learner.initials),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          learner.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF122C5B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          learner.lrn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7D91B2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 18,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    learner.grade,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF122C5B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    learner.section,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7D91B2),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge.crla(learner.crla),
              ),
            ),
            Expanded(
              flex: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge.philIri(learner.philIri),
              ),
            ),
            Expanded(
              flex: 13,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge.aralStatus(learner.aralStatus),
              ),
            ),
            Expanded(
              flex: 8,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  learner.gain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: learner.gain == '—' ? FontWeight.normal : FontWeight.w600,
                    color: learner.gain == '—' ? const Color(0xFF7D91B2) : const Color(0xFF1D8F5D),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  learner.lastAssessed,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7D91B2),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 52,
              child: Align(
                alignment: Alignment.center,
                child: Tooltip(
                  message: 'View learner profile',
                  child: GestureDetector(
                    onTap: onView,
                    child: const Icon(
                      Icons.visibility_outlined,
                      size: 18,
                      color: Color(0xFFADB8CC),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
