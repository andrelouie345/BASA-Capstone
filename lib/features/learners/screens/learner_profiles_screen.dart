import 'package:flutter/material.dart';
import '../../../data/mock_auth_data.dart';
import '../models/learner.dart';
import '../data/mock_learner_data.dart';
import '../widgets/learner_search_bar.dart';
import '../widgets/filter_chip.dart' as filter_chip_widget;
import '../widgets/learner_table_row.dart';
import '../widgets/pagination_controls.dart';
import '../widgets/add_learner_dialog.dart';
import '../widgets/learner_profile_panel.dart';

class LearnerProfilesScreen extends StatefulWidget {
  const LearnerProfilesScreen({super.key});

  @override
  State<LearnerProfilesScreen> createState() => _LearnerProfilesScreenState();
}

class _LearnerProfilesScreenState extends State<LearnerProfilesScreen> {
  final _searchController = TextEditingController();
  late List<Learner> _allLearners;
  late List<Learner> _filteredLearners;

  String _selectedGrade = 'All';
  String _selectedCrla = 'All';
  int _currentPage = 1;
  final int _itemsPerPage = 8;

  Learner? _selectedLearner;
  bool _isProfileOpen = false;
  bool _isProfileExpanded = false;

  final _grades = const ['All', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6'];
  final _crlas = const ['All', 'Non-Reader', 'Low', 'Average', 'Proficient'];

  @override
  void initState() {
    super.initState();
    _allLearners = List.from(MockLearnerData.learners);
    _filteredLearners = List.from(_allLearners);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final searchQuery = _searchController.text.toLowerCase();

    _filteredLearners = _allLearners.where((learner) {
      if (searchQuery.isNotEmpty) {
        final matchesSearch = learner.name.toLowerCase().contains(searchQuery) ||
            learner.lrn.toLowerCase().contains(searchQuery);
        if (!matchesSearch) return false;
      }

      if (_selectedGrade != 'All' && learner.grade != _selectedGrade) {
        return false;
      }

      if (_selectedCrla != 'All' && learner.crla != _selectedCrla) {
        return false;
      }

      return true;
    }).toList();

    _currentPage = 1;
    setState(() {});
  }

  void _onSearchChanged(String value) {
    _applyFilters();
  }

  void _onGradeFilterChanged(String grade) {
    setState(() => _selectedGrade = grade);
    _applyFilters();
  }

  void _onCrlaFilterChanged(String crla) {
    setState(() => _selectedCrla = crla);
    _applyFilters();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
  }

  void _showAddLearnerDialog() {
    showDialog(
      context: context,
      builder: (context) => AddLearnerDialog(
        onAdd: (data) {
          final newLearner = Learner(
            id: 'learner_${_allLearners.length + 1}',
            name: data['name']!,
            lrn: data['lrn']!,
            grade: data['grade']!,
            section: data['section']!,
            crla: 'Low',
            philIri: 'Frustration',
            aralStatus: 'Pending',
            gain: '—',
            lastAssessed: DateTime.now().toString().split(' ')[0],
          );

          setState(() {
            _allLearners.add(newLearner);
            _applyFilters();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Learner added successfully')),
          );
        },
      ),
    );
  }

  void _showExportMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Learner list exported successfully')),
    );
  }

  void _viewLearner(Learner learner) {
    setState(() {
      _selectedLearner = learner;
      _isProfileOpen = true;
    });
  }

  void _closeProfile() {
    setState(() {
      _isProfileOpen = false;
      _selectedLearner = null;
    });
  }

  void _toggleProfileExpanded() {
    if (_selectedLearner == null) return;
    setState(() => _isProfileExpanded = !_isProfileExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_filteredLearners.length / _itemsPerPage).ceil().clamp(1, double.infinity).toInt();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, _filteredLearners.length);
    final pageItems = _filteredLearners.sublist(startIndex, endIndex);

    final table = Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                Expanded(
                  child: LearnerSearchBar(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                  ),
                ),
                const SizedBox(width: 12),
                _buildActionButton(
                  label: 'Export',
                  icon: Icons.download_rounded,
                  color: const Color(0xFFF0F4FA),
                  textColor: const Color(0xFF6F7F9B),
                  borderColor: const Color(0xFFE3EAFE),
                  onTap: _showExportMessage,
                ),
                const SizedBox(width: 12),
                _buildActionButton(
                  label: 'Add Learner',
                  icon: Icons.person_add_rounded,
                  color: const Color(0xFF122C5B),
                  textColor: Colors.white,
                  onTap: _showAddLearnerDialog,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Grade:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF122C5B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _grades.map((grade) {
                          return filter_chip_widget.FilterPill(
                            label: grade,
                            isSelected: _selectedGrade == grade,
                            onTap: () => _onGradeFilterChanged(grade),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(width: 24),
                    const Text(
                      '|',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFE3EAFE),
                      ),
                    ),
                    const SizedBox(width: 24),
                    const Text(
                      'CRLA:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF122C5B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _crlas.map((crla) {
                          return filter_chip_widget.FilterPill(
                            label: crla,
                            isSelected: _selectedCrla == crla,
                            onTap: () => _onCrlaFilterChanged(crla),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      '${_filteredLearners.length} learner${_filteredLearners.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF122C5B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Container(
            color: const Color(0xFFF9FBFD),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Expanded(flex: 28, child: _buildTableHeader('LEARNER')),
                Expanded(flex: 18, child: _buildTableHeader('GRADE / SECTION')),
                Expanded(flex: 12, child: _buildTableHeader('CRLA')),
                Expanded(flex: 12, child: _buildTableHeader('PHIL-IRI')),
                Expanded(flex: 13, child: _buildTableHeader('ARAL STATUS')),
                Expanded(flex: 8, child: _buildTableHeader('GAIN')),
                Expanded(flex: 12, child: _buildTableHeader('LAST ASSESSED')),
                SizedBox(width: 52, child: _buildTableHeader('')),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: pageItems.length,
              itemBuilder: (context, index) {
                final learner = pageItems[index];
                final isSelected = _selectedLearner?.id == learner.id && _isProfileOpen;
                return LearnerTableRow(
                  learner: learner,
                  isSelected: isSelected,
                  onView: () => _viewLearner(learner),
                );
              },
            ),
          ),
          if (_filteredLearners.isNotEmpty)
            PaginationControls(
              currentPage: _currentPage,
              totalPages: totalPages,
              totalItems: _filteredLearners.length,
              itemsPerPage: _itemsPerPage,
              onPageChanged: _onPageChanged,
            ),
        ],
      ),
    );

    final contentWidth = MediaQuery.of(context).size.width;
    final panelVisible = _isProfileOpen && _selectedLearner != null;
    final panelWidth = panelVisible ? (_isProfileExpanded ? 500.0 : 340.0) : 0.0;

    return Row(
      children: [
        Expanded(
          child: table,
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: panelWidth,
          child: panelVisible
              ? LearnerProfilePanel(
                  learner: _selectedLearner!,
                  isExpanded: _isProfileExpanded,
                  onClose: _closeProfile,
                  onToggleExpand: _toggleProfileExpanded,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color textColor,
    Color? borderColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: borderColor != null ? Border.all(color: borderColor) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF7D91B2),
          letterSpacing: 0.5,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              MockAuthState.signOut();
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showPlaceholderMessage(String route) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Navigate to: $route (Coming soon)')),
    );
  }
}
