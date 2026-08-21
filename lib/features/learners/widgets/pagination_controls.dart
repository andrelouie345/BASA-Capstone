import 'package:flutter/material.dart';

class PaginationControls extends StatelessWidget {
  const PaginationControls({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.itemsPerPage,
    required this.onPageChanged,
  });

  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int itemsPerPage;
  final Function(int) onPageChanged;

  @override
  Widget build(BuildContext context) {
    final start = (currentPage - 1) * itemsPerPage + 1;
    final end = (currentPage * itemsPerPage).clamp(0, totalItems);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing $start–$end of $totalItems',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF7D91B2),
            ),
          ),
          Row(
            children: [
              // Previous button
              GestureDetector(
                onTap: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: currentPage > 1 ? const Color(0xFF122C5B) : const Color(0xFFBCC7DB),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Page numbers
              ...List.generate(
                totalPages,
                (index) {
                  final pageNum = index + 1;
                  final isSelected = pageNum == currentPage;

                  return GestureDetector(
                    onTap: () => onPageChanged(pageNum),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF122C5B) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '$pageNum',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : const Color(0xFF6F7F9B),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // Next button
              GestureDetector(
                onTap: currentPage < totalPages ? () => onPageChanged(currentPage + 1) : null,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: currentPage < totalPages ? const Color(0xFF122C5B) : const Color(0xFFBCC7DB),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
