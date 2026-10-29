// lib/ui/theme/colours_screen.dart
// Light / dark / follow the device, and the app's colours for each mode
// (docs/handoff/screens/auth.md, Colours). Saved on this device by
// ThemeSettingsViewModel; works before sign-in. A colour is tried on a
// sample card in the editor before it is saved.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/theme_settings.dart';
import '../basa_scope.dart';
import '../common/error_display.dart';
import '../common/screen_kit.dart';
import 'basa_colors.dart';
import 'basa_theme.dart';

class ColoursScreen extends StatefulWidget {
  const ColoursScreen({super.key});

  @override
  State<ColoursScreen> createState() => _ColoursScreenState();
}

class _ColoursScreenState extends State<ColoursScreen> {
  /// Which mode's colours the list edits; starts on the one showing now.
  ThemeBrightness? _editing;
  bool _busy = false;

  ThemeBrightness _editingOf(BuildContext context) =>
      _editing ?? (Theme.of(context).brightness == Brightness.dark ? ThemeBrightness.dark : ThemeBrightness.light);

  /// Calls the ViewModel and applies what it returns to the whole app.
  Future<void> _change(Future<ThemeSettings> Function() call) async {
    final apply = BasaThemeScope.of(context).apply;
    setState(() => _busy = true);
    try {
      apply(await call());
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, where: 'ColoursScreen');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmReset() async {
    final vm = BasaScope.of(context).theme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset all colours?'),
        content: const Text(
          'Every colour of light and dark mode goes back to the default, '
          'and the app follows the device\'s light or dark setting again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) await _change(vm.reset);
  }

  Future<void> _edit(BasaColor c, ThemeBrightness b, ThemeSettings settings) async {
    final vm = BasaScope.of(context).theme;
    final changes = settings.colorsFor(b);
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _ColourEditor(colour: c, brightness: b, changes: changes),
    );
    switch (result) {
      case null:
        return;
      case _UseDefault():
        await _change(() => vm.clearColor(b, c.name));
      case _Save(:final argb):
        await _change(() => vm.setColor(b, c.name, argb));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = BasaThemeScope.of(context);
    final settings = scope.settings;
    final editing = _editingOf(context);
    final brightness = editing == ThemeBrightness.light ? Brightness.light : Brightness.dark;
    final changes = settings.colorsFor(editing);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Colours'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _confirmReset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset all'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        final appearance = SectionCard(
          title: 'Appearance',
          icon: Icons.contrast,
          children: [
              SegmentedButton<ThemeModeChoice>(
                segments: const [
                  ButtonSegment(
                    value: ThemeModeChoice.system,
                    icon: Icon(Icons.brightness_auto),
                    label: Text('Device'),
                  ),
                  ButtonSegment(value: ThemeModeChoice.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                  ButtonSegment(value: ThemeModeChoice.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                ],
                selected: {settings.mode},
                onSelectionChanged: _busy
                    ? null
                    : (s) {
                        final vm = BasaScope.of(context).theme;
                        _change(() => vm.setMode(s.first));
                      },
              ),
              const SizedBox(height: 8),
              Text(
                'Saved on this device for everyone who uses it.',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
          ],
        );
        final modeSwitch = SegmentedButton<ThemeBrightness>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ThemeBrightness.light, label: Text('Light mode')),
            ButtonSegment(value: ThemeBrightness.dark, label: Text('Dark mode')),
          ],
          selected: {editing},
          onSelectionChanged: (s) => setState(() => _editing = s.first),
        );
        final changedCount = basaColors.where((c) => changes.containsKey(c.name)).length;
        final colourList = Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const IconBadge(Icons.palette_outlined, size: 34),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Colours', style: text.titleMedium)),
                      if (changedCount > 0) StatusChip('$changedCount changed', tone: StatusTone.warn),
                      // Wide enough: the mode switch beside the title.
                      if (box.maxWidth >= 600) ...[const SizedBox(width: 12), modeSwitch],
                    ]),
                    if (box.maxWidth < 600) ...[const SizedBox(height: 12), modeSwitch],
                  ],
                ),
              ),
              for (final (i, c) in basaColors.indexed) ...[
                if (i > 0) const Divider(height: 1),
                _ColourRow(
                  colour: c,
                  value: changes[c.name] ?? c.defaultFor(brightness),
                  changed: changes.containsKey(c.name),
                  onTap: _busy ? null : () => _edit(c, editing, settings),
                ),
              ],
            ],
          ),
        );
        final preview = _SamplePreview(brightness: brightness, changes: changes);
        if (wide) {
          // The preview stays in view beside the scrolling list.
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 32),
                      children: [appearance, const SizedBox(height: 16), colourList],
                    ),
                  ),
                  SizedBox(
                    width: 400,
                    child: Padding(padding: const EdgeInsets.fromLTRB(8, 16, 16, 16), child: preview),
                  ),
                ],
              ),
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [appearance, const SizedBox(height: 16), preview, const SizedBox(height: 12), colourList],
            ),
          ),
        );
      }),
    );
  }
}

class _ColourRow extends StatelessWidget {
  final BasaColor colour;
  final int value;
  final bool changed;
  final VoidCallback? onTap;
  const _ColourRow({required this.colour, required this.value, required this.changed, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: _Swatch(color: Color(value)),
      title: Text(colour.label),
      subtitle: Text(colour.usage, style: TextStyle(color: colors.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (changed)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: StatusChip('Changed', tone: StatusTone.warn),
            ),
          Text(hexOf(value), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final double size;
  const _Swatch({required this.color, this.size = 36});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}

/// A small screen drawn in [brightness] with [changes], so a colour is seen
/// where it is used.
class _SamplePreview extends StatelessWidget {
  final Brightness brightness;
  final Map<String, int> changes;
  const _SamplePreview({required this.brightness, required this.changes});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: basaThemeData(brightness, changes),
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          final text = Theme.of(context).textTheme;
          return Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outline),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Sample', style: text.titleSmall?.copyWith(color: colors.onSurface)),
                    const Spacer(),
                    _Dot(colors.tertiary, 'Online', colors.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Grade 4 · Sampaguita', style: text.titleSmall),
                        Text(
                          '32 learners · 5 not assessed',
                          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Pill('Grade ready', colors.primaryContainer, colors.onPrimaryContainer),
                            _Pill('Waiting for approval', colors.secondaryContainer, colors.onSecondaryContainer),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text('The section has no story for this region.', style: text.bodySmall?.copyWith(color: colors.error)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('Start')),
                    FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.secondary,
                        foregroundColor: colors.onSecondary,
                      ),
                      child: const Text('Accent'),
                    ),
                    OutlinedButton(onPressed: () {}, child: const Text('Later')),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Pill(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(
      label,
      style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  final Color textColor;
  const _Dot(this.color, this.label, this.textColor);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: textColor, fontSize: 12)),
    ],
  );
}

// ---- The colour editor ----

sealed class _EditResult {}

class _Save extends _EditResult {
  final int argb;
  _Save(this.argb);
}

class _UseDefault extends _EditResult {}

String hexOf(int argb) {
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final alpha = argb >>> 24;
  return alpha == 0xFF ? '#$rgb' : '#${alpha.toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
}

/// '#RRGGBB', 'RRGGBB' or '#AARRGGBB' → ARGB; null when it isn't one.
int? parseHex(String input) {
  final s = input.trim().replaceFirst('#', '');
  if (!RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(s)) return null;
  final v = int.parse(s, radix: 16);
  return s.length == 6 ? 0xFF000000 | v : v;
}

class _ColourEditor extends StatefulWidget {
  final BasaColor colour;
  final ThemeBrightness brightness;
  final Map<String, int> changes;
  const _ColourEditor({required this.colour, required this.brightness, required this.changes});

  @override
  State<_ColourEditor> createState() => _ColourEditorState();
}

class _ColourEditorState extends State<_ColourEditor> {
  late final Brightness _b = widget.brightness == ThemeBrightness.light ? Brightness.light : Brightness.dark;
  late int _argb = widget.changes[widget.colour.name] ?? widget.colour.defaultFor(_b);
  late final _hex = TextEditingController(text: hexOf(_argb));

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(int argb, {bool fromField = false}) {
    setState(() => _argb = argb);
    if (!fromField) _hex.text = hexOf(argb);
  }

  int _channel(int shift) => (_argb >> shift) & 0xFF;

  void _setChannel(int shift, double v) {
    final mask = ~(0xFF << shift) & 0xFFFFFFFF;
    _set((_argb & mask) | (v.round() << shift));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final isDefault = _argb == widget.colour.defaultFor(_b);
    final wasChanged = widget.changes.containsKey(widget.colour.name);
    final preview = {...widget.changes, widget.colour.name: _argb};

    return AlertDialog(
      title: Text(widget.colour.label),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.colour.usage} · ${_b == Brightness.light ? 'light' : 'dark'} mode',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _SamplePreview(brightness: _b, changes: preview),
            const SizedBox(height: 16),
            Row(
              children: [
                _Swatch(color: Color(_argb), size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(labelText: 'Hex', hintText: '#1F4E8C'),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]'))],
                    style: const TextStyle(fontFamily: 'monospace'),
                    onChanged: (s) {
                      final v = parseHex(s);
                      if (v != null) _set(v, fromField: true);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (label, shift) in const [('Red', 16), ('Green', 8), ('Blue', 0)])
              Row(
                children: [
                  SizedBox(width: 48, child: Text(label, style: text.bodySmall)),
                  Expanded(
                    child: Slider(
                      value: _channel(shift).toDouble(),
                      max: 255,
                      divisions: 255,
                      label: '${_channel(shift)}',
                      onChanged: (v) => _setChannel(shift, v),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text('${_channel(shift)}', textAlign: TextAlign.end, style: text.bodySmall),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Text('Default', style: text.labelMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _set(widget.colour.defaultFor(_b)),
                  child: _Swatch(color: Color(widget.colour.defaultFor(_b)), size: 28),
                ),
                const SizedBox(width: 8),
                Text(
                  hexOf(widget.colour.defaultFor(_b)),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (wasChanged)
          TextButton(onPressed: () => Navigator.pop(context, _UseDefault()), child: const Text('Use default')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          // Saving the default itself would mark the colour "changed" for nothing.
          onPressed: () => Navigator.pop(context, isDefault ? _UseDefault() : _Save(_argb)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
