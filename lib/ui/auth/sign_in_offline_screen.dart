// lib/ui/auth/sign_in_offline_screen.dart
// Sign in without a connection (docs/handoff/screens/auth.md, Sign in
// offline). Only the device owner (the last user who downloaded the data) can,
// within the offline window. The status card shows whose sign-in is saved,
// until when, and how many wrong passwords are left; every refusal is
// AuthViewModel's text, as is.
import 'package:flutter/material.dart';

import '../../core/models/offline_status.dart';
import '../basa_scope.dart';
import '../common/error_display.dart';

class SignInOfflineScreen extends StatefulWidget {
  /// Called after a sign-in that went through (the screen pops itself first).
  final VoidCallback onSignedIn;

  const SignInOfflineScreen({super.key, required this.onSignedIn});

  @override
  State<SignInOfflineScreen> createState() => _SignInOfflineScreenState();
}

class _SignInOfflineScreenState extends State<SignInOfflineScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();

  Future<OfflineStatus?>? _status;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _status ??= _loadStatus();
  }

  Future<OfflineStatus?> _loadStatus() async {
    final status = await BasaScope.of(context).auth.offlineStatus();
    // The saved owner's email is the only one that can sign in here.
    if (status != null && _email.text.isEmpty) _email.text = status.email;
    return status;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final auth = BasaScope.of(context).auth;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? refusal;
    try {
      refusal = await auth.signInOffline(email: _email.text.trim(), password: _password.text);
    } catch (e) {
      refusal = errorMessageFor(e, where: 'SignInOfflineScreen');
    }
    if (!mounted) return;
    if (refusal != null) {
      setState(() {
        _busy = false;
        _error = refusal;
        _status = _loadStatus(); // the attempts left changed
      });
      return;
    }
    Navigator.of(context).pop();
    widget.onSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final error = _error;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in offline')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: FutureBuilder<OfflineStatus?>(
                future: _status,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return ErrorMessage(
                      message: errorMessageFor(snap.error!, where: 'SignInOfflineScreen'),
                      onRetry: () => setState(() => _status = _loadStatus()),
                    );
                  }
                  final status = snap.data;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OfflineStatusCard(status: status),
                      const SizedBox(height: 12),
                      if (status != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Work is saved on this device and sent when you are back online.',
                                    style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
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
                                    ErrorMessage(message: error),
                                  ],
                                  const SizedBox(height: 20),
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _signIn,
                                    icon: _busy
                                        ? SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
                                          )
                                        : const Icon(Icons.cloud_off),
                                    label: const Text('Sign in offline'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Offline sign-in ready for x until y, n of m attempts left", or why there
/// is none. Shared with the About screen.
class OfflineStatusCard extends StatelessWidget {
  final OfflineStatus? status;
  const OfflineStatusCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final s = status;
    if (s == null) {
      return Card(
        color: colors.surfaceContainerHighest,
        child: ListTile(
          leading: Icon(Icons.cloud_off, color: colors.onSurfaceVariant),
          title: const Text('Offline sign-in is not set up on this device'),
          subtitle: const Text('Sign in online and download the latest data first. '
              'Then the device owner can sign in here without a connection.'),
        ),
      );
    }
    final now = DateTime.now();
    final expired = !s.until.isAfter(now);
    final left = (s.maxFailedAttempts - s.failedAttempts).clamp(0, s.maxFailedAttempts);
    final locked = left == 0;
    final ok = !expired && !locked;
    final tone = ok ? colors.primary : colors.error;
    return Card(
      color: ok ? colors.primaryContainer : colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ok ? Icons.verified_user_outlined : Icons.lock_clock, color: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ok ? 'Offline sign-in ready' : (expired ? 'Offline window has passed' : 'Too many wrong passwords'),
                    style: text.titleSmall?.copyWith(
                      color: ok ? colors.onPrimaryContainer : colors.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DefaultTextStyle.merge(
                    style: text.bodyMedium?.copyWith(
                      color: ok ? colors.onPrimaryContainer : colors.onErrorContainer,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('For ${s.email}'),
                        Text('${expired ? 'Ended' : 'Until'} ${formatDate(s.until.toLocal())} '
                            '(${s.windowDays} days after the last online sign-in)'),
                        Text('$left of ${s.maxFailedAttempts} attempts left'),
                        if (!ok) const Text('Sign in online to start a new offline window.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "27 Oct 2026, 14:05", local time.
String formatDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}
