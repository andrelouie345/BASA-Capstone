import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme.dart';
import '../../learners/widgets/status_badge.dart';
import '../models/assessment_record.dart';
import '../../learners/models/learner.dart';
import '../../learners/data/mock_learner_data.dart';

class AssessmentsScreen extends StatefulWidget {
  const AssessmentsScreen({
    super.key,
    this.initialTab = 'GST',
    this.preselectedLearner,
  });

  final String initialTab;
  final Learner? preselectedLearner;

  @override
  State<AssessmentsScreen> createState() => _AssessmentsScreenState();
}

class _AssessmentsScreenState extends State<AssessmentsScreen> {
  late String _activeTab;
  
  // Search controller for Assessment Records
  final _recordsSearchController = TextEditingController();

  // GST Configuration State
  final _classSectionController = TextEditingController(text: 'Sampaguita');
  final _maxRawScoreController = TextEditingController(text: '100');
  
  // GST Learner scores list (mock state)
  late List<Map<String, dynamic>> _gstLearners;

  // CRLA State & Subtask Controllers
  Learner? _crlaSelectedLearner;
  final _crlaAssessorController = TextEditingController(text: 'Admin Reyes');
  final _crlaLetterIdController = TextEditingController();
  final _crlaPhonemicController = TextEditingController();
  final _crlaDecodingController = TextEditingController();
  final _crlaOralFluencyController = TextEditingController();
  final _crlaComprehensionController = TextEditingController();

  // Phil-IRI State & Live Session
  Learner? _philIriSelectedLearner;
  final _philIriAssessorController = TextEditingController(text: 'Admin Reyes');
  bool _timerRunning = false;
  int _timerSeconds = 0;
  int _miscueCount = 0;
  Timer? _liveSessionTimer;

  // Phil-IRI Passages Controllers
  final List<String> _passageLevels = [
    'Pre-Primer',
    'Primer',
    'Grade 1',
    'Grade 2',
    'Grade 3',
    'Grade 4',
    'Grade 5',
    'Grade 6',
  ];
  late Map<String, TextEditingController> _wrControllers;
  late Map<String, TextEditingController> _compControllers;

  // Mock list of Assessment Records (initially pre-populated)
  late List<AssessmentRecord> _assessmentRecords;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;

    // Load initial learners for GST
    _gstLearners = [
      {
        'id': 'learner_001',
        'name': 'Maria Elena Santos',
        'lrn': '103402210012',
        'score': '',
        'percentage': 0.0,
        'classification': '—',
        'passage': '—',
      },
      {
        'id': 'learner_004',
        'name': 'Carlos Jose Mendoza',
        'lrn': '103402210044',
        'score': '',
        'percentage': 0.0,
        'classification': '—',
        'passage': '—',
      },
      {
        'id': 'learner_011',
        'name': 'Miguel Antonio Torres',
        'lrn': '103402210110',
        'score': '',
        'percentage': 0.0,
        'classification': '—',
        'passage': '—',
      },
      {
        'id': 'learner_013',
        'name': 'Roberto Juan Dizon',
        'lrn': '103402210133',
        'score': '',
        'percentage': 0.0,
        'classification': '—',
        'passage': '—',
      },
      {
        'id': 'learner_005',
        'name': 'Luz Divina Garcia',
        'lrn': '103402210057',
        'score': '',
        'percentage': 0.0,
        'classification': '—',
        'passage': '—',
      },
    ];

    // Seed mock records
    _assessmentRecords = [
      const AssessmentRecord(
        id: 'rec_001',
        learnerName: 'Maria Elena Santos',
        learnerId: '103402210012',
        assessmentType: 'GST',
        date: '2026-07-10',
        score: '65/100',
        percentage: '65%',
        readingLevel: 'Flagged',
        status: 'Completed',
        remarks: 'Needs individual Phil-IRI testing due to score below 70%',
      ),
      const AssessmentRecord(
        id: 'rec_002',
        learnerName: 'Juan Miguel dela Cruz',
        learnerId: '103402210018',
        assessmentType: 'CRLA',
        date: '2026-07-08',
        score: '115/146',
        percentage: '79%',
        readingLevel: 'Average',
        status: 'Completed',
        remarks: 'Exhibits average word reading speed and recognition.',
      ),
      const AssessmentRecord(
        id: 'rec_003',
        learnerName: 'Ana Marie Lim',
        learnerId: '103402210031',
        assessmentType: 'Phil-IRI',
        date: '2026-07-09',
        score: 'Grade 1 (Instructional)',
        percentage: '—',
        readingLevel: 'Instructional',
        status: 'Completed',
        remarks: 'Struggles with decoding. Recommended for ARAL intervention.',
      ),
      const AssessmentRecord(
        id: 'rec_004',
        learnerName: 'Carlos Jose Mendoza',
        learnerId: '103402210044',
        assessmentType: 'GST',
        date: '2026-07-07',
        score: '85/100',
        percentage: '85%',
        readingLevel: 'At-Level',
        status: 'Completed',
        remarks: 'Satisfactory screener results.',
      ),
    ];

    // CRLA listeners
    _crlaLetterIdController.addListener(_onCrlaScoreChanged);
    _crlaPhonemicController.addListener(_onCrlaScoreChanged);
    _crlaDecodingController.addListener(_onCrlaScoreChanged);
    _crlaOralFluencyController.addListener(_onCrlaScoreChanged);
    _crlaComprehensionController.addListener(_onCrlaScoreChanged);

    // Initialize Phil-IRI passage controllers
    _wrControllers = {};
    _compControllers = {};
    for (final lvl in _passageLevels) {
      _wrControllers[lvl] = TextEditingController();
      _compControllers[lvl] = TextEditingController();
      _wrControllers[lvl]!.addListener(_onPhilIriScoreChanged);
      _compControllers[lvl]!.addListener(_onPhilIriScoreChanged);
    }

    if (widget.preselectedLearner != null) {
      _philIriSelectedLearner = widget.preselectedLearner;
      _activeTab = 'Phil-IRI';
    }

    _classSectionController.addListener(_onGstConfigChanged);
    _maxRawScoreController.addListener(_onGstConfigChanged);
  }

  @override
  void dispose() {
    _recordsSearchController.dispose();
    _classSectionController.dispose();
    _maxRawScoreController.dispose();
    _crlaAssessorController.dispose();
    _crlaLetterIdController.dispose();
    _crlaPhonemicController.dispose();
    _crlaDecodingController.dispose();
    _crlaOralFluencyController.dispose();
    _crlaComprehensionController.dispose();
    _philIriAssessorController.dispose();
    _liveSessionTimer?.cancel();
    for (final lvl in _passageLevels) {
      _wrControllers[lvl]!.dispose();
      _compControllers[lvl]!.dispose();
    }
    super.dispose();
  }

  void _onCrlaScoreChanged() {
    setState(() {});
  }

  void _onPhilIriScoreChanged() {
    setState(() {});
  }

  void _onGstConfigChanged() {
    setState(() {
      for (var learner in _gstLearners) {
        _recalculateGstLearner(learner);
      }
    });
  }

  void _recalculateGstLearner(Map<String, dynamic> learner) {
    final rawScoreStr = learner['score'] as String;
    final maxScoreStr = _maxRawScoreController.text;
    
    if (rawScoreStr.isEmpty) {
      learner['percentage'] = 0.0;
      learner['classification'] = '—';
      learner['passage'] = '—';
      return;
    }

    final score = double.tryParse(rawScoreStr) ?? 0.0;
    final maxScore = double.tryParse(maxScoreStr) ?? 100.0;

    if (maxScore <= 0) {
      learner['percentage'] = 0.0;
      learner['classification'] = '—';
      learner['passage'] = '—';
      return;
    }

    final percentage = (score / maxScore) * 100.0;
    learner['percentage'] = percentage;

    if (percentage >= 70.0) {
      learner['classification'] = 'At-Level';
      learner['passage'] = '—';
    } else {
      learner['classification'] = 'Flagged';
      if (score < 40) {
        learner['passage'] = 'Beginning Reader Passage';
      } else if (score < 60) {
        learner['passage'] = 'Developing Reader Passage';
      } else {
        learner['passage'] = 'Intermediate Reader Passage';
      }
    }
  }

  int get _gstEnteredCount {
    return _gstLearners.where((l) => (l['score'] as String).isNotEmpty).length;
  }

  void _triggerAssessFromGst(Map<String, dynamic> gstLearner) {
    final matchedLearner = MockLearnerData.learners.firstWhere(
      (l) => l.lrn == gstLearner['lrn'],
      orElse: () => Learner(
        id: gstLearner['id'],
        name: gstLearner['name'],
        lrn: gstLearner['lrn'],
        grade: 'Grade 3',
        section: _classSectionController.text,
        crla: 'Low',
        philIri: 'Pending',
        aralStatus: 'Pending',
        gain: '—',
        lastAssessed: '—',
      ),
    );

    final startingPassage = gstLearner['passage'] as String;
    setState(() {
      _philIriSelectedLearner = matchedLearner;
      String levelKey = 'Pre-Primer';
      if (startingPassage.contains('Developing')) {
        levelKey = 'Grade 2';
      } else if (startingPassage.contains('Intermediate')) {
        levelKey = 'Grade 4';
      }
      _wrControllers[levelKey]!.text = '90'; // Mock starting entries
      _compControllers[levelKey]!.text = '75';
      _activeTab = 'Phil-IRI';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Selected ${matchedLearner.name} for Phil-IRI. Initialized starting passage level: $startingPassage.'),
      ),
    );
  }

  // CRLA Calculations
  double _getCrlaSubtaskPercentage(String scoreStr, double maxScore) {
    if (scoreStr.isEmpty) return 0.0;
    final score = double.tryParse(scoreStr) ?? 0.0;
    return ((score / maxScore) * 100.0).clamp(0.0, 100.0);
  }

  Color _getCrlaColorForPct(double pct) {
    if (pct < 50.0) return const Color(0xFFD84C66); // Red (Non-Reader)
    if (pct < 70.0) return const Color(0xFFE8912B); // Orange (Low)
    if (pct < 85.0) return const Color(0xFF1F67D6); // Blue (Average)
    return const Color(0xFF1D8F5D); // Green (Proficient)
  }

  String _getCrlaClassificationForPct(double pct) {
    if (pct < 50.0) return 'Non-Reader';
    if (pct < 70.0) return 'Low';
    if (pct < 85.0) return 'Average';
    return 'Proficient';
  }

  Map<String, dynamic> _calculateCrlaOverall() {
    final lId = double.tryParse(_crlaLetterIdController.text) ?? 0.0;
    final pa = double.tryParse(_crlaPhonemicController.text) ?? 0.0;
    final dec = double.tryParse(_crlaDecodingController.text) ?? 0.0;
    final of = double.tryParse(_crlaOralFluencyController.text) ?? 0.0;
    final comp = double.tryParse(_crlaComprehensionController.text) ?? 0.0;

    final hasInputs = _crlaLetterIdController.text.isNotEmpty ||
        _crlaPhonemicController.text.isNotEmpty ||
        _crlaDecodingController.text.isNotEmpty ||
        _crlaOralFluencyController.text.isNotEmpty ||
        _crlaComprehensionController.text.isNotEmpty;

    if (!hasInputs) {
      return {'score': 0.0, 'percentage': 0.0, 'level': 'Pending', 'color': Colors.grey};
    }

    final totalScore = lId + pa + dec + of + comp;
    final percentage = (totalScore / 146.0) * 100.0;
    
    String level;
    Color color;
    if (percentage < 50.0) {
      level = 'Non-Reader';
      color = const Color(0xFFD84C66);
    } else if (percentage < 70.0) {
      level = 'Low';
      color = const Color(0xFFE8912B);
    } else if (percentage < 85.0) {
      level = 'Average';
      color = const Color(0xFF1F67D6);
    } else {
      level = 'Proficient';
      color = const Color(0xFF1D8F5D);
    }

    return {
      'score': totalScore,
      'percentage': percentage,
      'level': level,
      'color': color,
    };
  }

  void _saveCrlaAssessment() {
    if (_crlaSelectedLearner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a learner first.')),
      );
      return;
    }

    final overall = _calculateCrlaOverall();
    if (overall['level'] == 'Pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter subtask scores before saving.')),
      );
      return;
    }

    final totalScore = (overall['score'] as double).toStringAsFixed(0);
    final totalPct = (overall['percentage'] as double).toStringAsFixed(0);

    final newRecord = AssessmentRecord(
      id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
      learnerName: _crlaSelectedLearner!.name,
      learnerId: _crlaSelectedLearner!.lrn,
      assessmentType: 'CRLA',
      date: DateTime.now().toString().split(' ')[0],
      score: '$totalScore/146',
      percentage: '$totalPct%',
      readingLevel: overall['level'],
      status: 'Completed',
      remarks: 'Assessed by ${_crlaAssessorController.text}. Profile: ${overall['level']}',
    );

    setState(() {
      _assessmentRecords.insert(0, newRecord);
      _crlaSelectedLearner = null;
      _crlaLetterIdController.clear();
      _crlaPhonemicController.clear();
      _crlaDecodingController.clear();
      _crlaOralFluencyController.clear();
      _crlaComprehensionController.clear();
      _activeTab = 'Assessment Records';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.green,
        content: Text('CRLA Assessment Saved successfully! View in logs.'),
      ),
    );
  }

  // Phil-IRI Calculations
  String _getPassageClassification(double wr, double comp) {
    if (wr == 0.0 && comp == 0.0) return 'Not Tested';
    if (wr >= 99.0 && comp >= 90.0) return 'Independent';
    if (wr < 95.0 || comp < 75.0) return 'Frustration';
    return 'Instructional';
  }

  Color _getPhilIriColorForLevel(String level) {
    return switch (level) {
      'Independent' => const Color(0xFF1D8F5D),
      'Instructional' => const Color(0xFFE8912B),
      'Frustration' => const Color(0xFFD84C66),
      _ => Colors.grey.shade400,
    };
  }

  String _calculateHighpointLevel() {
    String highestPassage = '—';
    String highestLevelResult = '—';
    int highestIndex = -1;

    for (int i = 0; i < _passageLevels.length; i++) {
      final lvl = _passageLevels[i];
      final wrStr = _wrControllers[lvl]!.text;
      final compStr = _compControllers[lvl]!.text;
      if (wrStr.isEmpty && compStr.isEmpty) continue;

      final wr = double.tryParse(wrStr) ?? 0.0;
      final comp = double.tryParse(compStr) ?? 0.0;
      if (wr == 0 && comp == 0) continue;

      final classification = _getPassageClassification(wr, comp);
      if (classification != 'Frustration' && classification != 'Not Tested') {
        if (i > highestIndex) {
          highestIndex = i;
          highestPassage = lvl;
          highestLevelResult = classification;
        }
      }
    }

    if (highestIndex != -1) {
      return '$highestPassage ($highestLevelResult)';
    }

    // Check if there was at least one tested passage (which must have been frustration)
    bool hasAnyTested = false;
    for (final lvl in _passageLevels) {
      final wrStr = _wrControllers[lvl]!.text;
      final compStr = _compControllers[lvl]!.text;
      if (wrStr.isNotEmpty || compStr.isNotEmpty) {
        final wr = double.tryParse(wrStr) ?? 0.0;
        final comp = double.tryParse(compStr) ?? 0.0;
        if (wr > 0 || comp > 0) {
          hasAnyTested = true;
          break;
        }
      }
    }

    if (hasAnyTested) {
      return 'Frustration (All tested passages)';
    }

    return 'Pending';
  }

  void _savePhilIriAssessment() {
    if (_philIriSelectedLearner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a learner first.')),
      );
      return;
    }

    final overallResult = _calculateHighpointLevel();
    if (overallResult == 'Pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter passage scores before saving.')),
      );
      return;
    }

    String readingLevel = 'Frustration';
    if (overallResult.contains('Independent')) {
      readingLevel = 'Independent';
    } else if (overallResult.contains('Instructional')) {
      readingLevel = 'Instructional';
    }

    final newRecord = AssessmentRecord(
      id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
      learnerName: _philIriSelectedLearner!.name,
      learnerId: _philIriSelectedLearner!.lrn,
      assessmentType: 'Phil-IRI',
      date: DateTime.now().toString().split(' ')[0],
      score: overallResult,
      percentage: '—',
      readingLevel: readingLevel,
      status: 'Completed',
      remarks: 'Assessed by ${_philIriAssessorController.text}. Highpoint result: $overallResult. Session Time: $_timerSeconds sec, Miscues: $_miscueCount',
    );

    setState(() {
      _assessmentRecords.insert(0, newRecord);
      
      // Stop timer and reset states
      _liveSessionTimer?.cancel();
      _timerRunning = false;
      _timerSeconds = 0;
      _miscueCount = 0;
      
      _philIriSelectedLearner = null;
      for (final lvl in _passageLevels) {
        _wrControllers[lvl]!.clear();
        _compControllers[lvl]!.clear();
      }
      _activeTab = 'Assessment Records';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.green,
        content: Text('Phil-IRI Assessment saved successfully! View in logs.'),
      ),
    );
  }

  // Live Timer triggers
  void _startLiveSession() {
    if (_timerRunning) return;
    setState(() {
      _timerRunning = true;
      _timerSeconds = 0;
      _miscueCount = 0;
    });

    _liveSessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _timerSeconds++;
      });
    });
  }

  void _stopLiveSession() {
    _liveSessionTimer?.cancel();
    setState(() {
      _timerRunning = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Session stopped. Elapsed: $_timerSeconds sec. Total Miscues: $_miscueCount.'),
      ),
    );
  }

  void _printReport() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.print_rounded, color: BasaTheme.primaryNavy),
              SizedBox(width: 10),
              Text(
                'Print Report Summary',
                style: TextStyle(fontWeight: FontWeight.w800, color: BasaTheme.primaryNavy),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'BASA READING SYSTEM - READING ASSESSMENT REPORT',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: BasaTheme.darkNavy),
                  ),
                  const SizedBox(height: 5),
                  Text('School: Mapayapa Elementary School   Date: ${DateTime.now().toString().split(' ')[0]}'),
                  Text('Section: ${_classSectionController.text}               Module: $_activeTab'),
                  const Divider(height: 24, thickness: 1.5, color: Color(0xFFE5ECF6)),
                  if (_activeTab == 'GST') ...[
                    const Text('GST Scores and Classifications:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(3),
                        1: FlexColumnWidth(1),
                        2: FlexColumnWidth(1),
                        3: FlexColumnWidth(2),
                      },
                      border: TableBorder.all(color: Colors.grey.shade300),
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(color: Color(0xFFEEF4FC)),
                          children: [
                            Padding(padding: EdgeInsets.all(6), child: Text('Learner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Padding(padding: EdgeInsets.all(6), child: Text('Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Padding(padding: EdgeInsets.all(6), child: Text('Pct', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Padding(padding: EdgeInsets.all(6), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                          ],
                        ),
                        ..._gstLearners.map((l) {
                          final pct = (l['percentage'] as double).toStringAsFixed(0);
                          return TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(6), child: Text(l['name'], style: const TextStyle(fontSize: 11))),
                              Padding(padding: const EdgeInsets.all(6), child: Text(l['score'].isEmpty ? '—' : l['score'], style: const TextStyle(fontSize: 11))),
                              Padding(padding: const EdgeInsets.all(6), child: Text(l['score'].isEmpty ? '—' : '$pct%', style: const TextStyle(fontSize: 11))),
                              Padding(padding: const EdgeInsets.all(6), child: Text(l['classification'], style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: l['classification'] == 'At-Level' ? Colors.green : (l['classification'] == 'Flagged' ? Colors.red : Colors.black)))),
                            ],
                          );
                        }),
                      ],
                    ),
                  ] else ...[
                    const Text('Assessments Record Log Summary:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(3),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.5),
                        3: FlexColumnWidth(2.5),
                      },
                      border: TableBorder.all(color: Colors.grey.shade300),
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(color: Color(0xFFEEF4FC)),
                          children: [
                            Padding(padding: EdgeInsets.all(6), child: Text('Learner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Padding(padding: EdgeInsets.all(6), child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Padding(padding: EdgeInsets.all(6), child: Text('Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            Padding(padding: EdgeInsets.all(6), child: Text('Reading Level', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                          ],
                        ),
                        ..._assessmentRecords.map((r) {
                          return TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(6), child: Text(r.learnerName, style: const TextStyle(fontSize: 10))),
                              Padding(padding: const EdgeInsets.all(6), child: Text(r.assessmentType, style: const TextStyle(fontSize: 10))),
                              Padding(padding: const EdgeInsets.all(6), child: Text(r.score, style: const TextStyle(fontSize: 10))),
                              Padding(padding: const EdgeInsets.all(6), child: Text(r.readingLevel, style: const TextStyle(fontSize: 10))),
                            ],
                          );
                        }),
                      ],
                    ),
                  ],
                  const SizedBox(height: 15),
                  const Text(
                    '* Document generated electronically via BASA. Press print to initiate standard hardware dialog.',
                    style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Color(0xFF7D91B2)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BasaTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                minimumSize: const Size(100, 40),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Document successfully sent to system printer.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Print Now'),
            ),
          ],
        );
      },
    );
  }

  void _showRecordDetails(AssessmentRecord record) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            record.learnerName,
            style: const TextStyle(fontWeight: FontWeight.bold, color: BasaTheme.primaryNavy),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Learner ID/LRN: ${record.learnerId}'),
              const SizedBox(height: 6),
              Text('Assessment: ${record.assessmentType}'),
              const SizedBox(height: 6),
              Text('Date: ${record.date}'),
              const SizedBox(height: 6),
              Text('Score: ${record.score}'),
              if (record.percentage != '—') ...[
                const SizedBox(height: 6),
                Text('Percentage: ${record.percentage}'),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('Reading Level: '),
                  StatusBadge.philIri(record.readingLevel),
                ],
              ),
              const SizedBox(height: 6),
              Text(record.remarks, style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assessments & Reading Diagnostics',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: BasaTheme.primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage screener results and diagnostic profiles',
                    style: TextStyle(
                      color: const Color(0xFF7D91B2),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF5A6D8D),
                  elevation: 0,
                  side: const BorderSide(color: Color(0xFFE5ECF6)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  minimumSize: const Size(120, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _printReport,
                icon: const Icon(Icons.print_rounded, size: 16),
                label: const Text(
                  'Print Report',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Horizontal tabs
          Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5ECF6)),
            ),
            child: Row(
              children: [
                _buildTabButton('GST', 'Group Screening (GST)'),
                _buildTabButton('CRLA', 'CRLA'),
                _buildTabButton('Phil-IRI', 'Phil-IRI'),
                _buildTabButton('Assessment Records', 'Assessment Records'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Content area — Phil-IRI scrolls naturally; other tabs use fixed height
          if (_activeTab == 'Phil-IRI')
            Expanded(
              child: SingleChildScrollView(
                child: _buildPhilIriTabContent(),
              ),
            )
          else
            Expanded(
              child: _buildActiveTabContent(),
            ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String key, String title) {
    final isSelected = _activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeTab = key;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected ? BasaTheme.darkNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF5A6D8D),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTab) {
      case 'GST':
        return _buildGstTabContent();
      case 'CRLA':
        return _buildCrlaTabContent();
      case 'Phil-IRI':
        return _buildPhilIriTabContent();
      case 'Assessment Records':
        return _buildRecordsTabContent();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- GST TAB ---
  Widget _buildGstTabContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool wide = width >= 900;

        final leftPanel = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5ECF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0B234B),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.layers_rounded, color: Colors.orange, size: 24),
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GST',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: BasaTheme.darkNavy,
                            ),
                          ),
                          Text(
                            'Group Screening Tool',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7D91B2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'A quick class-wide screener. Raw scores are entered per learner and the system classifies each as At-Level or Flagged for individual Phil-IRI assessment.',
                  style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF5A6D8D)),
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFFE5ECF6)),
                const SizedBox(height: 12),
                const Text(
                  'Teacher Workflow (TASKS 1–4)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: BasaTheme.primaryNavy),
                ),
                const SizedBox(height: 12),
                _buildWorkflowStep(1, 'Log in: teacher module dashboard displayed'),
                _buildWorkflowStep(2, 'Enter raw scores for the entire class roster'),
                _buildWorkflowStep(3, 'Exclude absent or pre-assessed learners'),
                _buildWorkflowStep(4, 'Click Assess on a flagged learner to open Phil-IRI session'),
                _buildWorkflowStep(5, 'System navigates to the correct starting passage from GST score'),
                const SizedBox(height: 24),
                const Divider(color: Color(0xFFE5ECF6)),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const TextSpan(
                        text: ' At-Level ≥ 70%   \n',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF5A6D8D)),
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const TextSpan(
                        text: ' Flagged < 70% — Phil-IRI needed',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF5A6D8D)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        final rightPanel = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5ECF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0B234B),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Administer Group Screening Test',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BasaTheme.primaryNavy),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter raw scores per learner. System auto-classifies and queues flagged learners for Phil-IRI.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7D91B2)),
              ),
              const SizedBox(height: 18),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CLASS SECTION',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF7D91B2)),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8FB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE5ECF6)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _classSectionController.text,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(value: 'Sampaguita', child: Text('Sampaguita (Grade 3)')),
                                DropdownMenuItem(value: 'Rosal', child: Text('Rosal (Grade 2)')),
                                DropdownMenuItem(value: 'Ilang-Ilang', child: Text('Ilang-Ilang (Grade 4)')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _classSectionController.text = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MAX SCORE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF7D91B2)),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _maxRawScoreController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              fillColor: const Color(0xFFF6F8FB),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE5ECF6)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE5ECF6)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFEEF4FC),
                      foregroundColor: BasaTheme.primaryNavy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(42, 42),
                    ),
                    onPressed: _printReport,
                    icon: const Icon(Icons.print_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5ECF6)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'CLASSIFICATION:',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('At-Level ≥ 70%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Flagged < 70% — Phil-IRI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                    ),
                    const Spacer(),
                    Text(
                      '$_gstEnteredCount/5 entered',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BasaTheme.primaryNavy),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              Container(
                color: const Color(0xFFF9FBFD),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: const [
                    SizedBox(width: 30, child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                    Expanded(flex: 6, child: Text('LEARNER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                    Expanded(flex: 2, child: Text('RAW SCORE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                    Expanded(flex: 2, child: Text('PERCENTAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                    Expanded(flex: 3, child: Text('CLASSIFICATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                    Expanded(flex: 4, child: Text('SUGGESTED PASSAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                    SizedBox(width: 90, child: Text('ACTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                  ],
                ),
              ),

              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _gstLearners.length,
                  separatorBuilder: (_, __) => const Divider(color: Color(0xFFEFF5FC), height: 1),
                  itemBuilder: (context, index) {
                    final item = _gstLearners[index];
                    final pctVal = item['percentage'] as double;
                    final classification = item['classification'] as String;
                    final passage = item['passage'] as String;
                    final isFlagged = classification == 'Flagged';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          Expanded(
                            flex: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: BasaTheme.darkNavy)),
                                const SizedBox(height: 2),
                                Text(item['lrn'], style: const TextStyle(fontSize: 10, color: Color(0xFF7D91B2))),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: SizedBox(
                                height: 36,
                                child: TextField(
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    fillColor: const Color(0xFFF6F8FB),
                                    hintText: '0',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFE5ECF6)),
                                    ),
                                  ),
                                  onChanged: (val) {
                                    setState(() {
                                      item['score'] = val;
                                      _recalculateGstLearner(item);
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              (item['score'] as String).isEmpty ? '—' : '${pctVal.toStringAsFixed(0)}%',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: BasaTheme.darkNavy),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: classification == '—'
                                ? const Text('—', style: TextStyle(color: Colors.grey))
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isFlagged
                                          ? Colors.red.withValues(alpha: 0.1)
                                          : Colors.green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      classification,
                                      style: TextStyle(
                                        color: isFlagged ? Colors.red : Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              passage,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isFlagged ? BasaTheme.darkNavy : const Color(0xFF7D91B2),
                                fontWeight: isFlagged ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: isFlagged
                                ? TextButton(
                                    style: TextButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFF1F1),
                                      foregroundColor: Colors.red,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _triggerAssessFromGst(item),
                                    child: const Text('Assess', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  )
                                : const Center(child: Text('—', style: TextStyle(color: Colors.grey))),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 320, child: leftPanel),
              const SizedBox(width: 20),
              Expanded(child: rightPanel),
            ],
          );
        } else {
          return SingleChildScrollView(
            child: Column(
              children: [
                leftPanel,
                const SizedBox(height: 20),
                SizedBox(height: 600, child: rightPanel),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildWorkflowStep(int index, String text, {bool checked = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: checked ? const Color(0xFFEDFBF5) : const Color(0xFFEEF4FC),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: checked
                ? const Icon(Icons.check_rounded, color: Color(0xFF1D8F5D), size: 14)
                : Text(
                    '$index',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: BasaTheme.primaryNavy),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF5A6D8D)),
            ),
          ),
        ],
      ),
    );
  }

  // --- CRLA TAB ---
  Widget _buildCrlaTabContent() {
    final learners = MockLearnerData.learners;
    final overall = _calculateCrlaOverall();
    final double overallScore = overall['score'] as double;
    final double overallPct = overall['percentage'] as double;
    final String overallLevel = overall['level'] as String;
    final Color overallColor = overall['color'] as Color;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;

        final leftPanel = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5ECF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0B234B),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDFBF5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.menu_book_rounded, color: Color(0xFF1D8F5D), size: 24),
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CRLA',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BasaTheme.darkNavy),
                          ),
                          Text(
                            'Comprehensive Rapid Literacy Assessment',
                            style: TextStyle(fontSize: 10, color: Color(0xFF7D91B2)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'A classroom assessment tool focused on diagnosing rapid word recognition, reading speed, decoding, and comprehension levels for primary school children.',
                  style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF5A6D8D)),
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFFE5ECF6)),
                const SizedBox(height: 12),
                const Text(
                  '5 ASSESSMENT AREAS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: BasaTheme.primaryNavy, letterSpacing: 0.5),
                ),
                const SizedBox(height: 14),
                _buildCrlaAreaLegendItem(const Color(0xFFD84C66), 'Letter Identification', 'Uppercase & lowercase recognition · max 26 pts'),
                _buildCrlaAreaLegendItem(const Color(0xFFE8912B), 'Phonemic Awareness', 'Blending, segmenting & rhyming · max 30 pts'),
                _buildCrlaAreaLegendItem(const Color(0xFF1F67D6), 'Decoding Skills', 'CVC words, digraphs & blends · max 20 pts'),
                _buildCrlaAreaLegendItem(const Color(0xFF8F6AE7), 'Oral Reading Fluency', 'Words correct per minute (WCPM) · max 60 pts'),
                _buildCrlaAreaLegendItem(const Color(0xFF1D8F5D), 'Comprehension', 'Literal & inferential questions · max 10 pts'),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFFE5ECF6)),
                const SizedBox(height: 12),
                const Text('CLASSIFICATION RANGES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2))),
                const SizedBox(height: 10),
                _buildClassificationRangeDot(const Color(0xFFD84C66), 'Non-Reader', '< 50% (< 73 pts)'),
                _buildClassificationRangeDot(const Color(0xFFE8912B), 'Low', '50–69% (73–101 pts)'),
                _buildClassificationRangeDot(const Color(0xFF1F67D6), 'Average', '70–84% (102–123 pts)'),
                _buildClassificationRangeDot(const Color(0xFF1D8F5D), 'Proficient', '≥ 85% (124–146 pts)'),
              ],
            ),
          ),
        );

        final rightPanel = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5ECF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0B234B),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Administer CRLA Assessment',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BasaTheme.primaryNavy),
                      ),
                      Text(
                        'Enter scores per subtask. Classification is computed in real time.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF7D91B2)),
                      ),
                    ],
                  ),
                  if (overallLevel != 'Pending')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: overallColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: overallColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: overallColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$overallLevel (${overallPct.toStringAsFixed(0)}%)',
                            style: TextStyle(color: overallColor, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // Student details row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LEARNER NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2))),
                        const SizedBox(height: 6),
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8FB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE5ECF6)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Learner>(
                              value: _crlaSelectedLearner,
                              hint: const Text('Select Learner', style: TextStyle(fontSize: 13)),
                              isExpanded: true,
                              items: learners.map((l) {
                                return DropdownMenuItem(value: l, child: Text(l.name, style: const TextStyle(fontSize: 13)));
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _crlaSelectedLearner = val;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LRN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2))),
                        const SizedBox(height: 6),
                        Container(
                          height: 44,
                          width: double.infinity,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF5FC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE5ECF6)),
                          ),
                          child: Text(
                            _crlaSelectedLearner?.lrn ?? '—',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: BasaTheme.darkNavy),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ASSESSOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2))),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 44,
                          child: TextField(
                            controller: _crlaAssessorController,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const Text(
                'SUBTASK SCORES',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: BasaTheme.primaryNavy, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),

              // Individual cards list
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildCrlaScoreCard('Letter Identification', 'Uppercase & lowercase recognition', 26.0, _crlaLetterIdController),
                    _buildCrlaScoreCard('Phonemic Awareness', 'Blending, segmenting & rhyming', 30.0, _crlaPhonemicController),
                    _buildCrlaScoreCard('Decoding Skills', 'CVC words, digraphs & blends', 20.0, _crlaDecodingController),
                    _buildCrlaScoreCard('Oral Reading Fluency', 'Words correct per minute (WCPM)', 60.0, _crlaOralFluencyController),
                    _buildCrlaScoreCard('Comprehension', 'Literal & inferential questions', 10.0, _crlaComprehensionController),
                    const SizedBox(height: 14),

                    // Guide & footer
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8FB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5ECF6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CLASSIFICATION GUIDE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2))),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildRangeIndicatorDot(const Color(0xFFD84C66), 'Non-Reader'),
                              _buildRangeIndicatorDot(const Color(0xFFE8912B), 'Low'),
                              _buildRangeIndicatorDot(const Color(0xFF1F67D6), 'Average'),
                              _buildRangeIndicatorDot(const Color(0xFF1D8F5D), 'Proficient'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Auto-classified per DepEd CRLA rubric · max 146 pts',
                          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF7D91B2)),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BasaTheme.primaryNavy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            minimumSize: const Size(150, 44),
                          ),
                          onPressed: _saveCrlaAssessment,
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Save & Classify', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ],
          ),
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 320, child: leftPanel),
              const SizedBox(width: 20),
              Expanded(child: rightPanel),
            ],
          );
        } else {
          return SingleChildScrollView(
            child: Column(
              children: [
                leftPanel,
                const SizedBox(height: 20),
                SizedBox(height: 650, child: rightPanel),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildCrlaAreaLegendItem(Color dotColor, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: BasaTheme.darkNavy)),
                Text(desc, style: const TextStyle(fontSize: 10, color: Color(0xFF7D91B2))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassificationRangeDot(Color color, String name, String range) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BasaTheme.darkNavy), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(range, style: const TextStyle(fontSize: 11, color: Color(0xFF7D91B2)), overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeIndicatorDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: BasaTheme.darkNavy)),
      ],
    );
  }

  Widget _buildCrlaScoreCard(String title, String desc, double maxScore, TextEditingController controller) {
    final scoreText = controller.text;
    final pct = _getCrlaSubtaskPercentage(scoreText, maxScore);
    final indicatorColor = _getCrlaColorForPct(pct);
    final classificationName = _getCrlaClassificationForPct(pct);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5ECF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: indicatorColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: BasaTheme.darkNavy)),
                    const SizedBox(height: 2),
                    Text(desc, style: const TextStyle(fontSize: 11, color: Color(0xFF7D91B2))),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'max ${maxScore.toInt()}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF7D91B2)),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 70,
                height: 38,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BasaTheme.darkNavy),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    fillColor: const Color(0xFFF6F8FB),
                    hintText: '0',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5ECF6)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: pct / 100.0,
                    minHeight: 6,
                    color: indicatorColor,
                    backgroundColor: const Color(0xFFEFF4FC),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                scoreText.isEmpty ? '0%' : '${pct.toStringAsFixed(0)}% ($classificationName)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: indicatorColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhilIriTabContent() {
    final learners = MockLearnerData.learners;
    final flaggedLearners = learners
        .where((l) => l.philIri == 'Frustration' || l.crla == 'Low' || l.crla == 'Non-Reader')
        .toList();
    final selectorList = flaggedLearners.isNotEmpty ? flaggedLearners : learners;
    final overallCalculatedLevel = _calculateHighpointLevel();
    final timerMin = (_timerSeconds ~/ 60).toString().padLeft(2, '0');
    final timerSec = (_timerSeconds % 60).toString().padLeft(2, '0');

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final wide = w >= 900;
        final passageCols = w >= 900 ? 4 : (w >= 600 ? 2 : 1);

        // ── LEFT INFO PANEL ────────────────────────────────────────────────
        final leftPanel = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5ECF6)),
            boxShadow: const [
              BoxShadow(color: Color(0x0A0B234B), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phil-IRI',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: BasaTheme.darkNavy)),
                        Text('Philippine Informal Reading Inventory',
                            style:
                                TextStyle(fontSize: 10, color: Color(0xFF7D91B2)),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'The diagnostic oral/silent test designed to determine overall student independent, instructional, and frustration levels.',
                style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF5A6D8D)),
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFFE5ECF6)),
              const SizedBox(height: 12),
              const Text('LIVE SESSION FEATURES',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: BasaTheme.primaryNavy,
                      letterSpacing: 0.5)),
              const SizedBox(height: 14),
              _buildWorkflowStep(1,
                  'Navigate to starting passage based on GST score',
                  checked: true),
              _buildWorkflowStep(
                  2, 'Record oral miscues correct-time speed logs',
                  checked: _timerSeconds > 0),
              _buildWorkflowStep(
                  3, 'Tap timer controls to capture reading fluency',
                  checked: !_timerRunning && _timerSeconds > 0),
              _buildWorkflowStep(
                  4, 'Validate comprehension questions and log scores',
                  checked: _gstEnteredCount > 0),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFFE5ECF6)),
              const SizedBox(height: 12),
              const Text('CLASSIFICATION RUBRIC',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: BasaTheme.primaryNavy,
                      letterSpacing: 0.5)),
              const SizedBox(height: 14),
              _buildPhilIriMatrixBadge('Independent', 'Green Indicator',
                  'Word Accuracy ≥ 99% AND Comprehension ≥ 90%'),
              _buildPhilIriMatrixBadge('Instructional', 'Orange Indicator',
                  'Word Accuracy 95–98% OR Comprehension 75–89%'),
              _buildPhilIriMatrixBadge('Frustration', 'Red Indicator',
                  'Word Accuracy < 95% OR Comprehension < 75%'),
            ],
          ),
        );

        // ── RIGHT MAIN PANEL ───────────────────────────────────────────────
        final rightPanel = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5ECF6)),
            boxShadow: const [
              BoxShadow(color: Color(0x0A0B234B), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header row
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Phil-IRI Diagnostic Session',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: BasaTheme.primaryNavy)),
                      Text(
                          'Conduct oral testing and log scores to determine reading profiles.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF7D91B2))),
                    ],
                  ),
                  if (overallCalculatedLevel != 'Pending')
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: overallCalculatedLevel.contains('Frustration')
                            ? const Color(0xFFFFF1F1)
                            : (overallCalculatedLevel.contains('Independent')
                                ? const Color(0xFFEDFBF5)
                                : const Color(0xFFFFF4E6)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: overallCalculatedLevel.contains('Frustration')
                              ? const Color(0xFFD84C66).withValues(alpha: 0.3)
                              : (overallCalculatedLevel.contains('Independent')
                                  ? const Color(0xFF1D8F5D).withValues(alpha: 0.3)
                                  : const Color(0xFFE8912B).withValues(alpha: 0.3)),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: overallCalculatedLevel.contains('Frustration')
                                  ? const Color(0xFFD84C66)
                                  : (overallCalculatedLevel.contains('Independent')
                                      ? const Color(0xFF1D8F5D)
                                      : const Color(0xFFE8912B)),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            overallCalculatedLevel,
                            style: TextStyle(
                              color: overallCalculatedLevel.contains('Frustration')
                                  ? const Color(0xFFD84C66)
                                  : (overallCalculatedLevel.contains('Independent')
                                      ? const Color(0xFF1D8F5D)
                                      : const Color(0xFFE8912B)),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Learner fields
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  // Learner Name
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 200),
                    child: IntrinsicWidth(
                      stepWidth: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('LEARNER NAME',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF7D91B2))),
                          const SizedBox(height: 6),
                          Container(
                            height: 44,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F8FB),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE5ECF6)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<Learner>(
                                value: _philIriSelectedLearner,
                                hint: const Text('Select Learner',
                                    style: TextStyle(fontSize: 13)),
                                isExpanded: true,
                                items: selectorList
                                    .map((l) => DropdownMenuItem(
                                        value: l,
                                        child: Text(l.name,
                                            style: const TextStyle(
                                                fontSize: 13))))
                                    .toList(),
                                onChanged: (val) =>
                                    setState(() => _philIriSelectedLearner = val),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // LRN
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('LRN',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF7D91B2))),
                      const SizedBox(height: 6),
                      Container(
                        height: 44,
                        width: 160,
                        alignment: Alignment.centerLeft,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF5FC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE5ECF6)),
                        ),
                        child: Text(
                          _philIriSelectedLearner?.lrn ?? '—',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: BasaTheme.darkNavy),
                        ),
                      ),
                    ],
                  ),
                  // Assessor
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ASSESSOR',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF7D91B2))),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 44,
                        width: 180,
                        child: TextField(
                          controller: _philIriAssessorController,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── LIVE SESSION CONTAINER ─────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF5FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCBE0FF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.mic_none_rounded,
                            color: Color(0xFF1F67D6), size: 20),
                        SizedBox(width: 8),
                        Text('LIVE SESSION CONTROLS',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: Color(0xFF1F67D6),
                                letterSpacing: 0.5)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Responsive Wrap: Start button + Timer + Miscues
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _timerRunning
                                ? const Color(0xFFD84C66)
                                : const Color(0xFF1F67D6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            minimumSize: const Size(160, 44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed:
                              _timerRunning ? _stopLiveSession : _startLiveSession,
                          icon: Icon(
                              _timerRunning
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                              size: 18),
                          label: Text(
                            _timerRunning ? 'Stop Recording' : 'Start Session',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBE0FF)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined,
                                  size: 16, color: Color(0xFF1F67D6)),
                              const SizedBox(width: 6),
                              Text('Timer: $timerMin:$timerSec',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: BasaTheme.darkNavy,
                                      fontFamily: 'monospace')),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBE0FF)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 16, color: Color(0xFFD84C66)),
                              const SizedBox(width: 6),
                              Text('Miscues: $_miscueCount',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: BasaTheme.darkNavy)),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () {
                                  if (_timerRunning) {
                                    setState(() => _miscueCount++);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                      color: Color(0xFFEEF5FF),
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.add,
                                      size: 16, color: Color(0xFF1F67D6)),
                                ),
                              ),
                              if (_miscueCount > 0) ...[
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (_miscueCount > 0) _miscueCount--;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFFFF1F1),
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.remove,
                                        size: 16, color: Color(0xFFD84C66)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── PASSAGE SCORES HEADER ──────────────────────────────────
              const Text('PASSAGE SCORES — MANUAL ENTRY',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: BasaTheme.primaryNavy,
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              const Text(
                'Enter Word Recognition % and Comprehension % per passage level. Leave at 0 if not tested.',
                style: TextStyle(fontSize: 11, color: Color(0xFF7D91B2)),
              ),
              const SizedBox(height: 14),

              // ── PASSAGE CARDS RESPONSIVE GRID ──────────────────────────
              // We build a Wrap manually sized per row
              _buildPassageGrid(passageCols),

              const SizedBox(height: 16),

              // ── FOOTER — Highpoint note + Save button ──────────────────
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Overall level calculated using Highpoint Method.',
                    style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade600),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BasaTheme.primaryNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      minimumSize: const Size(150, 44),
                    ),
                    onPressed: _savePhilIriAssessment,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Save & Classify',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        );

        // ── Layout: wide = side-by-side, narrow = stacked ─────────────
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 300, child: leftPanel),
              const SizedBox(width: 20),
              Expanded(child: rightPanel),
            ],
          );
        } else {
          return Column(
            children: [
              leftPanel,
              const SizedBox(height: 20),
              rightPanel,
            ],
          );
        }
      },
    );
  }

  /// Builds the responsive passage cards using a manual grid via LayoutBuilder.
  Widget _buildPassageGrid(int cols) {
    final rows = <Widget>[];
    for (int i = 0; i < _passageLevels.length; i += cols) {
      final rowItems = _passageLevels.skip(i).take(cols).toList();
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int j = 0; j < rowItems.length; j++) ...[
              Expanded(child: _buildPassageScoreCard(rowItems[j])),
              if (j < rowItems.length - 1) const SizedBox(width: 12),
            ],
            // Fill empty slots in last row
            for (int k = rowItems.length; k < cols; k++) ...[
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ],
        ),
      );
      if (i + cols < _passageLevels.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }

  Widget _buildPhilIriMatrixBadge(String title, String colorDesc, String rule) {
    final color = _getPhilIriColorForLevel(title);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
                Text(rule, style: const TextStyle(fontSize: 10, color: Color(0xFF5A6D8D))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassageScoreCard(String level) {
    final wrController = _wrControllers[level]!;
    final compController = _compControllers[level]!;

    final wr = double.tryParse(wrController.text) ?? 0.0;
    final comp = double.tryParse(compController.text) ?? 0.0;
    final hasInput = wrController.text.isNotEmpty || compController.text.isNotEmpty;

    final classification = _getPassageClassification(wr, comp);
    final indicatorColor = _getPhilIriColorForLevel(classification);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasInput
              ? indicatorColor.withValues(alpha: 0.35)
              : const Color(0xFFE5ECF6),
          width: hasInput ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x060B234B), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Card header: level name + classification badge
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: hasInput ? indicatorColor : const Color(0xFFBDCCE4),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  level,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: BasaTheme.darkNavy),
                ),
              ),
              if (hasInput)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: indicatorColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    classification,
                    style: TextStyle(
                        color: indicatorColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 10),
                  ),
                )
              else
                Text('Not tested',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade400)),
            ],
          ),
          const SizedBox(height: 12),

          // WORD RECOGNITION row
          const Text('WORD RECOGNITION %',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7D91B2),
                  letterSpacing: 0.3)),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 70,
                height: 36,
                child: TextField(
                  controller: wrController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,3}(\.\d{0,1})?')),
                  ],
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    hintText: '0',
                    hintStyle: TextStyle(
                        color: Colors.grey.shade400, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF6F8FB),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5ECF6)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: indicatorColor, width: 1.5),
                    ),
                    suffixText: '%',
                    suffixStyle: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${wr.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: hasInput ? indicatorColor : Colors.grey.shade400),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (wr / 100.0).clamp(0.0, 1.0),
                        minHeight: 6,
                        color: hasInput ? indicatorColor : const Color(0xFFE5ECF6),
                        backgroundColor: const Color(0xFFEFF4FC),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // COMPREHENSION row
          const Text('COMPREHENSION %',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7D91B2),
                  letterSpacing: 0.3)),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 70,
                height: 36,
                child: TextField(
                  controller: compController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,3}(\.\d{0,1})?')),
                  ],
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    hintText: '0',
                    hintStyle: TextStyle(
                        color: Colors.grey.shade400, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF6F8FB),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5ECF6)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: indicatorColor, width: 1.5),
                    ),
                    suffixText: '%',
                    suffixStyle: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${comp.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: hasInput ? indicatorColor : Colors.grey.shade400),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (comp / 100.0).clamp(0.0, 1.0),
                        minHeight: 6,
                        color: hasInput ? indicatorColor : const Color(0xFFE5ECF6),
                        backgroundColor: const Color(0xFFEFF4FC),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- RECORDS TAB ---
  Widget _buildRecordsTabContent() {
    final query = _recordsSearchController.text.toLowerCase();
    
    final filtered = _assessmentRecords.where((record) {
      final matchesSearch = record.learnerName.toLowerCase().contains(query) ||
          record.learnerId.toLowerCase().contains(query) ||
          record.assessmentType.toLowerCase().contains(query);
      return matchesSearch;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5ECF6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0B234B),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _recordsSearchController,
                    onChanged: (val) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search assessments by name, ID or type...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      fillColor: const Color(0xFFF6F8FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE5ECF6)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE5ECF6)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEEF4FC),
                  foregroundColor: BasaTheme.primaryNavy,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  minimumSize: const Size(100, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _printReport,
                icon: const Icon(Icons.print_rounded, size: 16),
                label: const Text('Print List', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Container(
            color: const Color(0xFFF9FBFD),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: const [
                Expanded(flex: 6, child: Text('LEARNER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                Expanded(flex: 3, child: Text('ASSESSMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                Expanded(flex: 3, child: Text('DATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                Expanded(flex: 4, child: Text('SCORE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                Expanded(flex: 4, child: Text('READING LEVEL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                Expanded(flex: 3, child: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
                SizedBox(width: 100, child: Text('ACTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7D91B2)))),
              ],
            ),
          ),
          
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No assessments matched your query.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(color: Color(0xFFEFF5FC), height: 1),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.learnerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: BasaTheme.darkNavy)),
                                  const SizedBox(height: 2),
                                  Text(item.learnerId, style: const TextStyle(fontSize: 10, color: Color(0xFF7D91B2))),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(item.assessmentType, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BasaTheme.darkNavy)),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(item.date, style: const TextStyle(fontSize: 13, color: Color(0xFF5A6D8D))),
                            ),
                            Expanded(
                              flex: 4,
                              child: Text(item.score, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: BasaTheme.darkNavy)),
                            ),
                            Expanded(
                              flex: 4,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: StatusBadge.philIri(item.readingLevel),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(item.status, style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                            ),
                            SizedBox(
                              width: 100,
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.visibility_outlined, size: 18, color: BasaTheme.primaryNavy),
                                    onPressed: () => _showRecordDetails(item),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.print_rounded, size: 18, color: Color(0xFF5A6D8D)),
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Printing assessment details of ${item.learnerName}...')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
