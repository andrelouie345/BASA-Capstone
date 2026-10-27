// lib/ui/common/screen_kit.dart
// Small pieces every screen reuses, so each screen file holds only what is
// its own: a body that loads from a ViewModel (loading / error / retry), an
// action runner that applies the error rule, dialogs, labelled values and a
// place to save exported files.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../viewmodels/app_viewmodels.dart';
import '../basa_scope.dart';
import 'error_display.dart';

/// The ViewModels (both builds). Read before any await.
AppViewModels vmsOf(BuildContext context) => BasaScope.of(context);

/// Loads [load] once (and again when [reloadKey] changes or the user asks),
/// shows a spinner meanwhile and the error rule on failure, then [builder].
/// [load] gets the ViewModels, read before the call (no context across an await).
class LoadView<T> extends StatefulWidget {
  final Future<T> Function(AppViewModels vms) load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;
  final Object? reloadKey;

  /// Names the screen in the log line of an unexpected error.
  final String where;

  const LoadView({super.key, required this.load, required this.builder, this.reloadKey, this.where = 'LoadView'});

  @override
  State<LoadView<T>> createState() => _LoadViewState<T>();
}

class _LoadViewState<T> extends State<LoadView<T>> {
  bool _loading = true;
  String? _error;
  T? _data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant LoadView<T> old) {
    super.didUpdateWidget(old);
    // After this frame: a ViewModel logs at once, and the debug console redraws on every log line.
    if (old.reloadKey != widget.reloadKey) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final vms = BasaScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load(vms);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessageFor(e, where: widget.where);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    if (_error != null) return ErrorMessage(message: _error!, onRetry: _load, fill: true);
    return widget.builder(context, _data as T, _load);
  }
}

/// Runs [action]; on failure shows the error rule in a snack bar and returns
/// null. On success shows [done] (when given) and returns the result.
Future<R?> runAction<R>(BuildContext context, Future<R> Function() action, {String? done, String where = 'BASA'}) async {
  final messenger = ScaffoldMessenger.of(context);
  final colors = Theme.of(context).colorScheme;
  try {
    final r = await action();
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    return r;
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      backgroundColor: colors.errorContainer,
      content: Text(errorMessageFor(e, where: where), style: TextStyle(color: colors.onErrorContainer)),
    ));
    return null;
  }
}

/// [runAction] for an action without a result: true when it succeeded.
Future<bool> runStep(BuildContext context, Future<void> Function() action, {String? done, String where = 'BASA'}) async =>
    await runAction<bool>(context, () async {
      await action();
      return true;
    }, done: done, where: where) ??
    false;

/// A plain message in a snack bar.
void showNote(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Asks yes / no. True only on [action].
Future<bool> confirm(BuildContext context,
    {required String title, String? body, String action = 'OK', bool destructive = false}) async {
  final colors = Theme.of(context).colorScheme;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return yes == true;
}

/// Shows a long text (a report, a result) that can be selected and copied.
Future<void> showTextDialog(BuildContext context, {required String title, required String text}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(width: 560, child: SingleChildScrollView(child: SelectableText(text))),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
  ),
);

/// One field of [askFields].
class FieldSpec {
  final String key;
  final String label;
  final String initial;
  final String? hint;
  final bool number;
  final bool multiline;
  final bool optional;

  const FieldSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.hint,
    this.number = false,
    this.multiline = false,
    this.optional = false,
  });
}

/// A dialog with text fields; returns key → trimmed text, or null when
/// cancelled. Required fields must not be empty.
Future<Map<String, String>?> askFields(BuildContext context,
    {required String title, required List<FieldSpec> fields, String action = 'Save', String? note}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => _FieldsDialog(title: title, fields: fields, action: action, note: note),
  );
}

class _FieldsDialog extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final String action;
  final String? note;
  const _FieldsDialog({required this.title, required this.fields, required this.action, this.note});

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.initial),
  };
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop({for (final e in _c.entries) e.key: e.value.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.note != null)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.note!)),
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _c[f.key],
                      decoration: InputDecoration(labelText: f.label, hintText: f.hint),
                      keyboardType: f.number
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : f.multiline
                          ? TextInputType.multiline
                          : TextInputType.text,
                      minLines: f.multiline ? 2 : 1,
                      maxLines: f.multiline ? 5 : 1,
                      validator: (v) => !f.optional && (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

/// Picks one of [options] in a dialog; null when cancelled.
Future<T?> pickOne<T>(BuildContext context,
    {required String title, required List<T> options, required String Function(T) label}) {
  return showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final o in options)
          SimpleDialogOption(onPressed: () => Navigator.of(context).pop(o), child: Text(label(o))),
      ],
    ),
  );
}

/// A label and its value on one line.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A titled card around [children].
class SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  const SectionCard({super.key, required this.title, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Centered text for an empty list.
class EmptyNote extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyNote(this.text, {super.key, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// A scrolling page body with a readable width and padding.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const PageBody({super.key, required this.children, this.maxWidth = 960});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(children)),
          ),
        ),
      ],
    );
  }

  static List<Widget> _spaced(List<Widget> c) => [
    for (var i = 0; i < c.length; i++) ...[if (i > 0) const SizedBox(height: 12), c[i]],
  ];
}

/// Where exported files go: the app documents folder, then BASA/exports (created on first use).
Future<String> exportFolder() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}BASA${Platform.pathSeparator}exports');
  await dir.create(recursive: true);
  return dir.path;
}

/// A path for a new export named [fileName] in [exportFolder].
Future<String> exportPath(String fileName) async =>
    '${await exportFolder()}${Platform.pathSeparator}${fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';

/// Saves [text] as [fileName] in the export folder; returns the full path.
Future<String> saveTextExport(String fileName, String text) async {
  final path = await exportPath(fileName);
  await File(path).writeAsString(text);
  return path;
}

/// Says where a file was saved, the path selectable.
Future<void> showSaved(BuildContext context, String path) =>
    showTextDialog(context, title: 'Saved', text: 'The file was saved to:\n$path');

/// A text field for a file on this device (desktop admin tasks take a path).
class FilePathField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  const FilePathField({super.key, required this.controller, required this.label, this.hint});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint ?? r'e.g. C:\Users\me\Downloads\file.xlsx',
      prefixIcon: const Icon(Icons.insert_drive_file_outlined),
    ),
  );
}

/// Today as yyyy-mm-dd.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Asks for a date; returns it as yyyy-mm-dd, or null.
Future<String?> pickDate(BuildContext context, {String? initial}) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: DateTime.tryParse(initial ?? '') ?? now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 2),
  );
  return d == null ? null : isoDate(d);
}
