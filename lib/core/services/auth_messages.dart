// lib/core/services/auth_messages.dart
// Sign-in and session messages as a user reads them: no exception type names,
// no console commands (screens show these as they are).
import 'dart:io';

import 'package:supabase/supabase.dart';

const notSignedInMessage = 'Not signed in. Sign in first.';
const needsOnlineSignInMessage = 'This needs an online sign-in. Sign in again while connected.';
const mustChangePasswordMessage = 'You must change your password first.';
const cantReachServerMessage = "can't reach the server. Check the connection, or sign in offline on your own device.";

/// The reason after "Sign-in failed: " / "Password change failed: ". The raw
/// error belongs in the log, not in the message.
String authFailureMessage(Object error) {
  if (error is AuthRetryableFetchException || error is SocketException) return cantReachServerMessage;
  if (error is AuthException) return error.message;
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring('Exception: '.length) : text;
}
