import '../models/learner.dart';

class MockLearnerData {
  static const List<Learner> learners = [
    // Learner 1
    Learner(
      id: 'learner_001',
      name: 'Maria Elena Santos',
      lrn: '103402210012',
      grade: 'Grade 3',
      section: 'Sampaguita',
      crla: 'Low',
      philIri: 'Frustration',
      aralStatus: 'Active',
      gain: '+14%',
      lastAssessed: '2026-07-10',
    ),
    // Learner 2
    Learner(
      id: 'learner_002',
      name: 'Juan Miguel dela Cruz',
      lrn: '103402210018',
      grade: 'Grade 2',
      section: 'Rosal',
      crla: 'Average',
      philIri: 'Instructional',
      aralStatus: 'Not Enrolled',
      gain: '—',
      lastAssessed: '2026-07-08',
    ),
    // Learner 3
    Learner(
      id: 'learner_003',
      name: 'Ana Marie Lim',
      lrn: '103402210031',
      grade: 'Grade 4',
      section: 'Ilang-Ilang',
      crla: 'Non-Reader',
      philIri: 'Frustration',
      aralStatus: 'Active',
      gain: '+16%',
      lastAssessed: '2026-07-09',
    ),
    // Learner 4
    Learner(
      id: 'learner_004',
      name: 'Carlos Jose Mendoza',
      lrn: '103402210044',
      grade: 'Grade 3',
      section: 'Sampaguita',
      crla: 'Proficient',
      philIri: 'Independent',
      aralStatus: 'Completed',
      gain: '+24%',
      lastAssessed: '2026-07-07',
    ),
    // Learner 5
    Learner(
      id: 'learner_005',
      name: 'Luz Divina Garcia',
      lrn: '103402210057',
      grade: 'Grade 2',
      section: 'Rosal',
      crla: 'Low',
      philIri: 'Frustration',
      aralStatus: 'Active',
      gain: '+8%',
      lastAssessed: '2026-07-11',
    ),
    // Learner 6
    Learner(
      id: 'learner_006',
      name: 'Pedro Alfonso Ramos',
      lrn: '103402210063',
      grade: 'Grade 5',
      section: 'Waling-Waling',
      crla: 'Average',
      philIri: 'Instructional',
      aralStatus: 'Pending',
      gain: '+3%',
      lastAssessed: '2026-07-06',
    ),
    // Learner 7
    Learner(
      id: 'learner_007',
      name: 'Rosa Mae Flores',
      lrn: '103402210079',
      grade: 'Grade 4',
      section: 'Ilang-Ilang',
      crla: 'Low',
      philIri: 'Frustration',
      aralStatus: 'Active',
      gain: '+13%',
      lastAssessed: '2026-07-10',
    ),
    // Learner 8 (Page 1 last)
    Learner(
      id: 'learner_008',
      name: 'Patricia Anne Martinez',
      lrn: '103402210085',
      grade: 'Grade 6',
      section: 'Sampaguita',
      crla: 'Proficient',
      philIri: 'Independent',
      aralStatus: 'Completed',
      gain: '+22%',
      lastAssessed: '2026-07-05',
    ),
    // Page 2
    // Learner 9
    Learner(
      id: 'learner_009',
      name: 'Francisco David Torres',
      lrn: '103402210091',
      grade: 'Grade 2',
      section: 'Rosal',
      crla: 'Non-Reader',
      philIri: 'Frustration',
      aralStatus: 'Active',
      gain: '+11%',
      lastAssessed: '2026-07-09',
    ),
    // Learner 10
    Learner(
      id: 'learner_010',
      name: 'Veronica Marie Aquino',
      lrn: '103402210104',
      grade: 'Grade 3',
      section: 'Ilang-Ilang',
      crla: 'Average',
      philIri: 'Instructional',
      aralStatus: 'Active',
      gain: '+7%',
      lastAssessed: '2026-07-10',
    ),
    // Learner 11
    Learner(
      id: 'learner_011',
      name: 'Miguel Anthony Santos',
      lrn: '103402210110',
      grade: 'Grade 4',
      section: 'Sampaguita',
      crla: 'Low',
      philIri: 'Instructional',
      aralStatus: 'Active',
      gain: '+12%',
      lastAssessed: '2026-07-11',
    ),
    // Learner 12
    Learner(
      id: 'learner_012',
      name: 'Josephine Rose Domingo',
      lrn: '103402210127',
      grade: 'Grade 5',
      section: 'Waling-Waling',
      crla: 'Non-Reader',
      philIri: 'Frustration',
      aralStatus: 'Pending',
      gain: '+5%',
      lastAssessed: '2026-07-08',
    ),
    // Learner 13
    Learner(
      id: 'learner_013',
      name: 'Roberto Manuel Gonzales',
      lrn: '103402210133',
      grade: 'Grade 3',
      section: 'Rosal',
      crla: 'Proficient',
      philIri: 'Independent',
      aralStatus: 'Completed',
      gain: '+19%',
      lastAssessed: '2026-07-07',
    ),
    // Learner 14
    Learner(
      id: 'learner_014',
      name: 'Sandra Patricia Reyes',
      lrn: '103402210149',
      grade: 'Grade 6',
      section: 'Ilang-Ilang',
      crla: 'Average',
      philIri: 'Instructional',
      aralStatus: 'Active',
      gain: '+9%',
      lastAssessed: '2026-07-09',
    ),
    // Learner 15
    Learner(
      id: 'learner_015',
      name: 'Andres Emilio Fernandez',
      lrn: '103402210155',
      grade: 'Grade 2',
      section: 'Sampaguita',
      crla: 'Low',
      philIri: 'Frustration',
      aralStatus: 'Active',
      gain: '+6%',
      lastAssessed: '2026-07-10',
    ),
    // Learner 16 (Page 2 last)
    Learner(
      id: 'learner_016',
      name: 'Isabelle Sofia Rivera',
      lrn: '103402210161',
      grade: 'Grade 4',
      section: 'Waling-Waling',
      crla: 'Average',
      philIri: 'Instructional',
      aralStatus: 'Not Enrolled',
      gain: '—',
      lastAssessed: '2026-07-06',
    ),
    // Page 3
    // Learner 17
    Learner(
      id: 'learner_017',
      name: 'Fernando Jose Cabral',
      lrn: '103402210177',
      grade: 'Grade 5',
      section: 'Sampaguita',
      crla: 'Non-Reader',
      philIri: 'Frustration',
      aralStatus: 'Active',
      gain: '+10%',
      lastAssessed: '2026-07-11',
    ),
    // Learner 18
    Learner(
      id: 'learner_018',
      name: 'Georgina Ruth Ortega',
      lrn: '103402210183',
      grade: 'Grade 3',
      section: 'Rosal',
      crla: 'Proficient',
      philIri: 'Independent',
      aralStatus: 'Completed',
      gain: '+21%',
      lastAssessed: '2026-07-08',
    ),
    // Learner 19
    Learner(
      id: 'learner_019',
      name: 'Lazaro Emmanuel Rubio',
      lrn: '103402210199',
      grade: 'Grade 6',
      section: 'Ilang-Ilang',
      crla: 'Average',
      philIri: 'Instructional',
      aralStatus: 'Active',
      gain: '+4%',
      lastAssessed: '2026-07-09',
    ),
    // Learner 20 (Page 3 last)
    Learner(
      id: 'learner_020',
      name: 'Mariana Sylvia Vargas',
      lrn: '103402210205',
      grade: 'Grade 2',
      section: 'Waling-Waling',
      crla: 'Low',
      philIri: 'Instructional',
      aralStatus: 'Active',
      gain: '+17%',
      lastAssessed: '2026-07-10',
    ),
  ];

  static List<Learner> filterLearners({
    required String searchQuery,
    required String gradeFilter,
    required String crlaFilter,
  }) {
    var filtered = List<Learner>.from(learners);

    // Search filter
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filtered = filtered.where((learner) {
        return learner.name.toLowerCase().contains(query) ||
            learner.lrn.toLowerCase().contains(query);
      }).toList();
    }

    // Grade filter
    if (gradeFilter != 'All') {
      filtered = filtered.where((learner) => learner.grade == gradeFilter).toList();
    }

    // CRLA filter
    if (crlaFilter != 'All') {
      filtered = filtered.where((learner) => learner.crla == crlaFilter).toList();
    }

    return filtered;
  }
}
