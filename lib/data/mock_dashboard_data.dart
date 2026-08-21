class DashboardStats {
  const DashboardStats({
    required this.learners,
    required this.flaggedPhilIri,
    required this.todaysSessions,
    required this.materialsAvailable,
  });

  final int learners;
  final int flaggedPhilIri;
  final int todaysSessions;
  final int materialsAvailable;
}

class ReadingTrendPoint {
  const ReadingTrendPoint({
    required this.month,
    required this.value,
  });

  final String month;
  final double value;
}

class AralSession {
  const AralSession({
    required this.time,
    required this.learner,
    required this.duration,
    required this.activity,
    required this.status,
  });

  final String time;
  final String learner;
  final String duration;
  final String activity;
  final String status;
}

class MockDashboardData {
  static const DashboardStats stats = DashboardStats(
    learners: 20,
    flaggedPhilIri: 10,
    todaysSessions: 4,
    materialsAvailable: 20,
  );

  static const List<ReadingTrendPoint> readingTrend = [
    ReadingTrendPoint(month: 'Feb', value: 42),
    ReadingTrendPoint(month: 'Mar', value: 46),
    ReadingTrendPoint(month: 'Apr', value: 51),
    ReadingTrendPoint(month: 'May', value: 58),
    ReadingTrendPoint(month: 'Jun', value: 63),
    ReadingTrendPoint(month: 'Jul', value: 68),
  ];

  static const List<AralSession> sessions = [
    AralSession(
      time: '07:30',
      learner: 'Maria Elena Santos',
      duration: '30 min',
      activity: 'Phonemic Awareness',
      status: 'Scheduled',
    ),
    AralSession(
      time: '08:00',
      learner: 'Ana Marie Lim',
      duration: '30 min',
      activity: 'Fluency Practice',
      status: 'In Progress',
    ),
    AralSession(
      time: '09:15',
      learner: 'Jose Rafael Dela Cruz',
      duration: '45 min',
      activity: 'Reading Comprehension',
      status: 'Scheduled',
    ),
    AralSession(
      time: '10:00',
      learner: 'Mia Gabrielle Ramos',
      duration: '30 min',
      activity: 'Word Recognition',
      status: 'Scheduled',
    ),
  ];
}
