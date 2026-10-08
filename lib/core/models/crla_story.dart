// lib/core/models/crla_story.dart
import 'crla_language.dart';
class CrlaStory {
  final int? id;
  final int regionId;
  final String language;
  final int grade;
  final int storyNo;
  final String title;
  final int wordCount;
  final int? sourceStoryNo;

  CrlaStory({
    this.id,
    required this.regionId,
    required this.language,
    required this.grade,
    required this.storyNo,
    required this.title,
    required this.wordCount,
    this.sourceStoryNo,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'region_id': regionId,
        'language': normalizeCrlaLanguage(language),
        'grade': grade,
        'story_no': storyNo,
        'title': title,
        'word_count': wordCount,
        'source_story_no': sourceStoryNo,
      };

  factory CrlaStory.fromMap(Map<String, Object?> m) => CrlaStory(
        id: m['id'] as int?,
        regionId: m['region_id'] as int,
        language: m['language'] as String,
        grade: m['grade'] as int,
        storyNo: m['story_no'] as int,
        title: m['title'] as String,
        wordCount: m['word_count'] as int,
        sourceStoryNo: m['source_story_no'] as int?,
      );
}