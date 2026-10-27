// lib/ui/auth/change_password_screen.dart
// Set a new password (docs/handoff/screens/auth.md, Change password). Opened
// from the account menu, or shown by the app shell in place of the home while
// AuthViewModel.mustChangePassword is set (an admin-made account's first
// sign-in): then it can't be left except by signing out. The password rules
// are the server's; its refusal is AuthViewModel's text, as is.
import 'package:flutter/material.dart';

import '../basa_scope.dart';
import '../common/error_display.dart';

class ChangePasswordScreen extends StatefulWidget {
  /// The forced change: no back button, a "Sign out" instead.
  final bool forced;

  /// Called after the password changed (a pushed screen pops itself first).
  final VoidCallback? onChanged;

  /// Forced only: called after signing out instead.
  final VoidCallback? onSignedOut;

  const ChangePasswordScreen({super.key, this.forced = false, this.onChanged, this.onSignedOut});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final auth = BasaScope.of(context).auth;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? refusal;
    try {
      refusal = await auth.changePassword(_password.text);
    } catch (e) {
      refusal = errorMessageFor(e, where: 'ChangePasswordScreen');
    }
    if (!mounted) return;
    if (refusal != null) {
      setState(() {
        _busy = false;
        _error = refusal;
      });
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Password changed.')));
    final note = auth.offlineWarning;
    if (note != null && note.isNotEmpty) messenger.showSnackBar(SnackBar(content: Text(note)));
    if (!widget.forced) navigator.pop();
    widget.onChanged?.call();
  }

  Future<void> _signOut() async {
    final auth = BasaScope.of(context).auth;
    try {
      await auth.signOut();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, where: 'ChangePasswordScreen');
    }
    widget.onSignedOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final error = _error;
    final user = BasaScope.of(context).auth.currentUser;

    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Change password'),
          automaticallyImplyLeading: !widget.forced,
          actions: [
            if (widget.forced)
              TextButton.icon(
                onPressed: _busy ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.forced) ...[
                            Row(
                              children: [
                                Icon(Icons.key, color: colors.primary),
                                const SizedBox(width: 10),
                                Expanded(child: Text('Choose your own password', style: text.titleMedium)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Your account was made with a temporary password. '
                              'Set a new one before you continue.',
                              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (user != null) ...[
                            Text(user.email, style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: !_show,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                            decoration: InputDecoration(
                              labelText: 'New password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _show ? 'Hide passwords' : 'Show passwords',
                                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _show = !_show),
                              ),
                            ),
                            validator: (v) => (v ?? '').isEmpty ? 'Enter a new password.' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirm,
                            focusNode: _confirmFocus,
                            enabled: !_busy,
                            obscureText: !_show,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _save(),
                            decoration: const InputDecoration(
                              labelText: 'Type it again',
                              prefixIcon: Icon(Icons.lock_reset),
                            ),
                            validator: (v) => v != _password.text ? 'The two passwords are not the same.' : null,
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 16),
                            ErrorMessage(message: error),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _save,
                            child: _busy
                                ? SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
                                  )
                                : const Text('Save password'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Needs a connection. Your offline sign-in uses the new password afterwards.',
                            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
