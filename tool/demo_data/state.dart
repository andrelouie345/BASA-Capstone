// The demo builder's resume state (<dir>/state.json): which steps are done and
// the ids it captured. Saved after every change, so a run that stops halfway
// continues where it stopped. A corrupt file stops the builder (never a
// silent start over, which would duplicate the world).
import 'dart:convert';
import 'dart:io';

class DemoState {
  final File _file;
  final Set<String> _done;
  final Map<String, int> ids;

  DemoState._(this._file, this._done, this.ids);

  static Future<DemoState> load(Directory dir) async {
    final file = File('${dir.path}${Platform.pathSeparator}state.json');
    if (!file.existsSync()) return DemoState._(file, {}, {});
    try {
      final m = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return DemoState._(
        file,
        {...(m['done'] as List).cast<String>()},
        {...(m['ids'] as Map).cast<String, int>()},
      );
    } catch (e) {
      throw FormatException('${file.path} (the demo builder state) is unreadable: fix or delete it by hand. $e');
    }
  }

  bool done(String step) => _done.contains(step);

  Future<void> markDone(String step) async {
    _done.add(step);
    await _save();
  }

  Future<void> putId(String key, int id) async {
    ids[key] = id;
    await _save();
  }

  /// Written to a temporary file first, then renamed: a crash mid-write
  /// never leaves a half file.
  Future<void> _save() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({'done': [..._done]..sort(), 'ids': ids}));
    await tmp.rename(_file.path);
  }
}
