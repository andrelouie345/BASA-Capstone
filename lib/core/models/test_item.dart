// lib/core/models/test_item.dart
class TestItem {
  final int? id;
  final String name;
  const TestItem({this.id, required this.name});

  Map<String, Object?> toMap() => {if (id != null) 'id': id, 'name': name};

  factory TestItem.fromMap(Map<String, Object?> map) =>
      TestItem(id: map['id'] as int?, name: map['name'] as String);
}