// lib/ui/auth/server_settings_form.dart
// The cloud and LAN server settings (URL + anon key, the server's public key),
// used inside the sign-in screen's "Server settings" dropdown and reusable by
// the Server settings screen (docs/handoff/screens/auth.md). Works before
// sign-in. Keys are never shown back: the field starts empty, a hint shows
// the masked saved key, and an empty field keeps it.
import 'package:flutter/material.dart';

import '../../viewmodels/server_config_viewmodel.dart';
import '../basa_scope.dart';
import '../common/error_display.dart';

class ServerSettingsForm extends StatefulWidget {
  /// Called after a save, with the settings as saved.
  final ValueChanged<ServerConfigView>? onSaved;
  const ServerSettingsForm({super.key, this.onSaved});

  @override
  State<ServerSettingsForm> createState() => _ServerSettingsFormState();
}

class _ServerSettingsFormState extends State<ServerSettingsForm> {
  ServerConfigView? _view;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view ??= BasaScope.of(context).serverConfig.show();
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (view == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ServerBlock(
          title: 'Cloud server',
          url: view.cloudUrl,
          keyMasked: view.cloudKeyMasked,
          save: (vm, url, key) => vm.setCloud(url: url, anonKey: key),
          onSaved: _saved,
        ),
        const SizedBox(height: 16),
        _ServerBlock(
          title: 'LAN server (school network)',
          url: view.lanUrl,
          keyMasked: view.lanKeyMasked,
          save: (vm, url, key) => vm.setLan(url: url, anonKey: key),
          onSaved: _saved,
        ),
      ],
    );
  }

  void _saved(ServerConfigView view) {
    setState(() => _view = view);
    widget.onSaved?.call(view);
  }
}

class _ServerBlock extends StatefulWidget {
  final String title;
  final String url;
  final String keyMasked;
  final Future<void> Function(ServerConfigViewModel vm, String? url, String? key) save;
  final ValueChanged<ServerConfigView> onSaved;

  const _ServerBlock({
    required this.title,
    required this.url,
    required this.keyMasked,
    required this.save,
    required this.onSaved,
  });

  @override
  State<_ServerBlock> createState() => _ServerBlockState();
}

class _ServerBlockState extends State<_ServerBlock> {
  late final _url = TextEditingController(text: widget.url);
  final _key = TextEditingController();
  bool _saving = false;
  String? _error;
  bool _justSaved = false;

  @override
  void initState() {
    super.initState();
    _url.addListener(_edited);
    _key.addListener(_edited);
  }

  void _edited() {
    if (_justSaved || _error != null) {
      setState(() {
        _justSaved = false;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  bool get _changed => _url.text.trim() != widget.url || _key.text.trim().isNotEmpty;

  Future<void> _save() async {
    final vm = BasaScope.of(context).serverConfig;
    final url = _url.text.trim();
    final key = _key.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(vm, url == widget.url ? null : url, key.isEmpty ? null : key);
      _key.clear();
      _justSaved = true;
      widget.onSaved(vm.show());
    } catch (e) {
      _error = errorMessageFor(e, where: 'ServerSettingsForm');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final keySet = widget.keyMasked != '(not set)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: text.labelLarge?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Server URL', hintText: 'https://…'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _key,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Anon key (public key)',
            hintText: keySet ? 'Saved: ${widget.keyMasked} · leave empty to keep' : 'Not set',
            helperText: 'Never the service_role key.',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_justSaved) ...[
              Icon(Icons.check_circle, size: 18, color: colors.tertiary),
              const SizedBox(width: 6),
              Text('Saved on this device', style: TextStyle(color: colors.tertiary)),
            ],
            const Spacer(),
            ListenableBuilder(
              listenable: Listenable.merge([_url, _key]),
              builder: (context, _) => OutlinedButton(
                onPressed: _saving || !_changed ? null : _save,
                child: _saving
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        if (_error != null) ...[const SizedBox(height: 8), ErrorMessage(message: _error!)],
      ],
    );
  }
}
