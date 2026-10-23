// lib/core/services/auth_messages.dart
// Sign-in and session messages as a user reads them: no exception type names,
// no console commands (screens show these as they are).
import 'dart:io';

import 'package:supabase/supabase.dart';

const notSignedInMessage = 'Not signed in. Sign in first.';
const needsOnlineSignInMessage = 'This needs an online sign-in. Sign in again while connected.';
const mustChangePasswordMessage = 'You must change your password first.';
const cantReachServerMessage = "can't reach the server. Check the connection, or sign in offline on your own device.";

/// The server's own text for a refused Edge Function call (create-user,
/// bootstrap-admin): its `error` field, else the details or the HTTP reason.
String edgeFunctionErrorMessage(Object error) {
  if (error is SocketException) return cantReachServerMessage;
  if (error is! FunctionException) return authFailureMessage(error);
  final details = error.details;
  final message = details is Map ? details['error'] : null;
  return '${message ?? details ?? error.reasonPhrase ?? 'server error ${error.status}'}';
}

/// The reason after "Sign-in failed: " / "Password change failed: ". The raw
/// error belongs in the log, not in the message.
String authFailureMessage(Object error) {
  if (error is AuthRetryableFetchException || error is SocketException) return cantReachServerMessage;
  if (error is AuthException) return error.message;
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring('Exception: '.length) : text;
}
