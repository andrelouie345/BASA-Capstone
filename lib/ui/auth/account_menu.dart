// lib/ui/auth/account_menu.dart
// The signed-in user's menu for an app bar: Change password, Server
// settings, Colours, About, and Sign out (docs/handoff/screens/auth.md, Sign
// out: a menu item, not a screen). Sign out asks first; work not yet sent
// stays on this device.
import 'package:flutter/material.dart';

import '../basa_scope.dart';
import '../common/error_display.dart';
import '../common/signed_in_user.dart';
import '../theme/colours_screen.dart';
import 'about_screen.dart';
import 'change_password_screen.dart';
import 'server_settings_screen.dart';

enum _Item { password, servers, colours, about, signOut }

class AccountMenu extends StatelessWidget {
  /// "BASA" or "BASA Tutor", for About.
  final String appTitle;

  /// Called after signing out, so the app shell shows the sign-in screen.
  final VoidCallback onSignedOut;

  const AccountMenu({super.key, required this.appTitle, required this.onSignedOut});

  @override
  Widget build(BuildContext context) {
    final auth = BasaScope.of(context).auth;
    final user = auth.currentUser;
    return PopupMenuButton<_Item>(
      tooltip: 'Account',
      icon: user == null ? const Icon(Icons.account_circle_outlined) : UserAvatar(user: user, radius: 16),
      onSelected: (item) => _open(context, item),
      itemBuilder: (context) => [
        if (user != null)
          PopupMenuItem<_Item>(
            enabled: false,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(user.fullName.isEmpty ? user.email : user.fullName),
              subtitle: Text('${roleLabel(user)}${auth.isOffline ? ' · offline' : ''}'),
            ),
          ),
        if (user != null) const PopupMenuDivider(),
        // Changing a password needs the server: hidden while signed in offline.
        if (!auth.isOffline)
          const PopupMenuItem(
            value: _Item.password,
            child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.key), title: Text('Change password')),
          ),
        const PopupMenuItem(
          value: _Item.servers,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_ethernet),
            title: Text('Server settings'),
          ),
        ),
        const PopupMenuItem(
          value: _Item.colours,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.palette_outlined),
            title: Text('Colours'),
          ),
        ),
        const PopupMenuItem(
          value: _Item.about,
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.info_outline), title: Text('About')),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _Item.signOut,
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout), title: Text('Sign out')),
        ),
      ],
    );
  }

  void _open(BuildContext context, _Item item) {
    final navigator = Navigator.of(context);
    switch (item) {
      case _Item.password:
        navigator.push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
      case _Item.servers:
        navigator.push(MaterialPageRoute(builder: (_) => const ServerSettingsScreen()));
      case _Item.colours:
        navigator.push(MaterialPageRoute(builder: (_) => const ColoursScreen()));
      case _Item.about:
        navigator.push(MaterialPageRoute(builder: (_) => AboutScreen(appTitle: appTitle)));
      case _Item.signOut:
        confirmSignOut(context, onSignedOut: onSignedOut);
    }
  }
}

/// Asks, then signs out and calls [onSignedOut].
Future<void> confirmSignOut(BuildContext context, {required VoidCallback onSignedOut}) async {
  final auth = BasaScope.of(context).auth;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.logout),
      title: const Text('Sign out?'),
      content: Text(
        auth.isOffline
            ? 'Work not yet sent stays on this device. You can sign in offline again while the offline window lasts.'
            : 'Work not yet sent stays on this device. Send it before another person signs in here.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sign out')),
      ],
    ),
  );
  if (yes != true) return;
  try {
    await auth.signOut();
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e, where: 'AccountMenu');
  }
  onSignedOut();
}
