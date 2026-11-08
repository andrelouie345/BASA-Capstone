// lib/ui/common/search.dart
// Searching long lists. A list with more than [kSearchableThreshold] items gets
// a search box (pickers, pickOne dialogs); list screens put a [SearchField] in
// their FilterBar. Matching is case-insensitive on any part of the text, and
// works on the list already loaded (no ViewModel call).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lists longer than this get a search box.
const kSearchableThreshold = 5;

/// True when [query] is empty or is part of one of [fields] (ignoring case).
bool matchesSearch(String query, Iterable<String?> fields) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return fields.any((f) => f != null && f.toLowerCase().contains(q));
}

/// The search box of a list screen (goes in its FilterBar).
class SearchField extends StatelessWidget {
  final String label;
  final ValueChanged<String> onChanged;
  const SearchField({super.key, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
    decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: label),
    onChanged: onChanged,
  );
}

/// A dialog with a search box over [options]; null when cancelled.
/// Typing filters, arrow keys move the highlight, Enter picks it, Esc closes.
Future<T?> showSearchPick<T>(BuildContext context,
    {required String title, required List<T> options, required String Function(T) label}) {
  return showDialog<T>(
    context: context,
    builder: (context) => _SearchPickDialog<T>(title: title, options: options, label: label),
  );
}

class _SearchPickDialog<T> extends StatefulWidget {
  final String title;
  final List<T> options;
  final String Function(T) label;
  const _SearchPickDialog({super.key, required this.title, required this.options, required this.label});

  @override
  State<_SearchPickDialog<T>> createState() => _SearchPickDialogState<T>();
}

class _SearchPickDialogState<T> extends State<_SearchPickDialog<T>> {
  final _highlightKey = GlobalKey();
  String _query = '';
  int _highlight = 0;

  List<T> get _shown => [for (final o in widget.options) if (matchesSearch(_query, [widget.label(o)])) o];

  void _move(int by) {
    final n = _shown.length;
    if (n == 0) return;
    setState(() => _highlight = (_highlight + by).clamp(0, n - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _highlightKey.currentContext;
      if (c == null) return;
      Scrollable.ensureVisible(c,
          alignmentPolicy: by > 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    });
  }

  void _pickHighlighted() {
    final shown = _shown;
    if (shown.isNotEmpty) Navigator.of(context).pop(shown[_highlight.clamp(0, shown.length - 1)]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shown;
    // The keyboard comes up by itself only where there is a real one.
    final desktop = switch (theme.platform) {
      TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
      _ => false,
    };
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Text(widget.title, style: theme.textTheme.headlineSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
                },
                child: TextField(
                  autofocus: desktop,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search'),
                  textInputAction: TextInputAction.done,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _highlight = 0;
                  }),
                  onSubmitted: (_) => _pickHighlighted(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No matches', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: shown.length,
                      itemBuilder: (context, i) => ListTile(
                        key: i == _highlight ? _highlightKey : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                        selected: i == _highlight,
                        selectedTileColor: theme.colorScheme.secondaryContainer,
                        selectedColor: theme.colorScheme.onSecondaryContainer,
                        title: Text(widget.label(shown[i])),
                        onTap: () => Navigator.of(context).pop(shown[i]),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
