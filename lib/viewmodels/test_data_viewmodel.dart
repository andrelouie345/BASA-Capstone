// lib/viewmodels/test_data_viewmodel.dart
import '../core/console/logger.dart';
import '../core/models/test_item.dart';
import '../core/repositories/test_repository.dart';

class TestDataViewModel {
  final ScopedLogger _log;
  TestRepository _repo;
  List<TestItem> items = [];

  TestDataViewModel({required TestRepository repo, Logger? logger})
      : _repo = repo,
        _log = ScopedLogger(logger, 'TestDataViewModel');

  void useRepository(TestRepository repo, String label) {
    _repo = repo;
    _log('switched backend -> $label');
  }

  Future<void> refresh() async {
    _log('refresh()');
    items = await _repo.getAll();
  }

  Future<void> add(String name) async {
    _log('add(name: "$name")');
    await _repo.add(name);
    await refresh();
  }

  Future<void> delete(int id) async {
    _log('delete(id: $id)');
    await _repo.delete(id);
    await refresh();
  }
}