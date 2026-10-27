// lib/ui/auth/sign_in_screen.dart
// Sign in online to the cloud or LAN server (docs/handoff/screens/auth.md,
// Sign in (online)). The "Server settings" dropdown sets up a new device
// before anyone can sign in; it opens by itself while the chosen server has
// no URL. A version refusal is shown with VersionRefusalCard; every other
// refusal is AuthViewModel's text, as is.
import 'package:flutter/material.dart';

import '../../viewmodels/server_config_viewmodel.dart';
import '../basa_scope.dart';
import '../common/error_display.dart';
import '../common/version_notice.dart';
import '../theme/colours_screen.dart';
import 'server_settings_form.dart';

enum _Target { cloud, lan }

class SignInScreen extends StatefulWidget {
  /// "BASA" or "BASA Tutor".
  final String appTitle;

  /// Called after a sign-in that went through.
  final VoidCallback onSignedIn;

  const SignInScreen({super.key, required this.appTitle, required this.onSignedIn});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();

  _Target _target = _Target.cloud;
  ServerConfigView? _servers;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _servers ??= BasaScope.of(context).serverConfig.show();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String _urlOf(_Target t) => switch (t) {
    _Target.cloud => _servers?.cloudUrl ?? '',
    _Target.lan => _servers?.lanUrl ?? '',
  };

  Future<void> _signIn() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final auth = BasaScope.of(context).auth;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? refusal;
    try {
      refusal = await auth.signIn(target: _target.name, email: _email.text.trim(), password: _password.text);
    } catch (e) {
      refusal = errorMessageFor(e, where: 'SignInScreen');
    }
    if (!mounted) return;
    if (refusal != null) {
      setState(() {
        _busy = false;
        _error = refusal;
      });
      return;
    }
    // Signed in. The notices outlive this screen, so they go to the app's
    // messenger (captured before the await).
    for (final note in [auth.versionWarning, auth.offlineWarning]) {
      if (note != null && note.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(note), duration: const Duration(seconds: 8)));
      }
    }
    widget.onSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final noUrl = _urlOf(_target).isEmpty;
    final error = _error;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Masthead(appTitle: widget.appTitle),
                        const SizedBox(height: 28),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Sign in', style: text.titleLarge),
                                const SizedBox(height: 4),
                                Text(
                                  'The first sign-in on a device needs a connection.',
                                  style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                                ),
                                const SizedBox(height: 20),
                                SegmentedButton<_Target>(
                                  segments: const [
                                    ButtonSegment(
                                      value: _Target.cloud,
                                      icon: Icon(Icons.cloud_outlined),
                                      label: Text('Cloud'),
                                    ),
                                    ButtonSegment(
                                      value: _Target.lan,
                                      icon: Icon(Icons.lan_outlined),
                                      label: Text('School LAN'),
                                    ),
                                  ],
                                  selected: {_target},
                                  onSelectionChanged: _busy
                                      ? null
                                      : (s) => setState(() {
                                          _target = s.first;
                                          _error = null;
                                        }),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _email,
                                  enabled: !_busy,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  autocorrect: false,
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.alternate_email),
                                  ),
                                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your email.' : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _password,
                                  focusNode: _passwordFocus,
                                  enabled: !_busy,
                                  obscureText: !_showPassword,
                                  autofillHints: const [AutofillHints.password],
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _signIn(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: _showPassword ? 'Hide password' : 'Show password',
                                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                                      onPressed: () => setState(() => _showPassword = !_showPassword),
                                    ),
                                  ),
                                  validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
                                ),
                                if (error != null) ...[
                                  const SizedBox(height: 16),
                                  versionRefusalKind(error) != null
                                      ? VersionRefusalCard(message: error)
                                      : ErrorMessage(message: error),
                                ],
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: _busy || noUrl ? null : _signIn,
                                  child: _busy
                                      ? SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
                                        )
                                      : const Text('Sign in'),
                                ),
                                if (noUrl) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'No ${_target == _Target.cloud ? 'cloud' : 'LAN'} server is set on this device yet. '
                                    'Set it in Server settings below.',
                                    style: text.bodySmall?.copyWith(color: colors.secondary),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            // A new key per server, so choosing one with no URL opens it;
                            // saving a URL doesn't close it under the user.
                            key: ValueKey('servers-${_target.name}'),
                            initiallyExpanded: noUrl,
                            leading: const Icon(Icons.settings_ethernet),
                            title: const Text('Server settings'),
                            subtitle: Text(
                              noUrl ? 'Needed before the first sign-in' : _urlOf(_target),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            shape: const Border(),
                            collapsedShape: const Border(),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [ServerSettingsForm(onSaved: (v) => setState(() => _servers = v))],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Colours',
                icon: const Icon(Icons.palette_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ColoursScreen())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's name over a ruled-paper band: the "reading notebook" look.
class _Masthead extends StatelessWidget {
  final String appTitle;
  const _Masthead({required this.appTitle});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(18)),
          child: Icon(Icons.auto_stories, color: colors.onPrimary, size: 34),
        ),
        const SizedBox(height: 14),
        Text(
          appTitle,
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5, color: colors.primary),
        ),
        const SizedBox(height: 4),
        Text(
          'ARAL-Reading · CRLA · Phil-IRI',
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 0.3),
        ),
        const SizedBox(height: 14),
        CustomPaint(size: const Size(160, 14), painter: _RulePainter(colors.secondary, colors.outlineVariant)),
      ],
    );
  }
}

class _RulePainter extends CustomPainter {
  final Color margin;
  final Color line;
  _RulePainter(this.margin, this.line);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final y in [2.0, 7.0, 12.0]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    canvas.drawLine(
      Offset(size.width * 0.18, 0),
      Offset(size.width * 0.18, size.height),
      Paint()
        ..color = margin
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_RulePainter old) => old.margin != margin || old.line != line;
}
