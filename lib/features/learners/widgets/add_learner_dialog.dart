import 'package:flutter/material.dart';

class AddLearnerDialog extends StatefulWidget {
  const AddLearnerDialog({super.key, required this.onAdd});

  final Function(Map<String, String>) onAdd;

  @override
  State<AddLearnerDialog> createState() => _AddLearnerDialogState();
}

class _AddLearnerDialogState extends State<AddLearnerDialog> {
  final _nameController = TextEditingController();
  final _lrnController = TextEditingController();
  String? _selectedGrade;
  String? _selectedSection;

  final grades = ['Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6'];
  final sections = ['Sampaguita', 'Rosal', 'Ilang-Ilang', 'Waling-Waling'];

  @override
  void dispose() {
    _nameController.dispose();
    _lrnController.dispose();
    super.dispose();
  }

  void _handleAdd() {
    if (_nameController.text.isEmpty ||
        _lrnController.text.isEmpty ||
        _selectedGrade == null ||
        _selectedSection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    widget.onAdd({
      'name': _nameController.text,
      'lrn': _lrnController.text,
      'grade': _selectedGrade!,
      'section': _selectedSection!,
    });

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Learner'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Learner Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _lrnController,
              decoration: InputDecoration(
                labelText: 'LRN',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedGrade,
              items: grades.map((grade) {
                return DropdownMenuItem(value: grade, child: Text(grade));
              }).toList(),
              onChanged: (value) => setState(() => _selectedGrade = value),
              decoration: InputDecoration(
                labelText: 'Grade',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedSection,
              items: sections.map((section) {
                return DropdownMenuItem(value: section, child: Text(section));
              }).toList(),
              onChanged: (value) => setState(() => _selectedSection = value),
              decoration: InputDecoration(
                labelText: 'Section',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _handleAdd,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF122C5B),
            foregroundColor: Colors.white,
          ),
          child: const Text('Add Learner'),
        ),
      ],
    );
  }
}
