// User-facing sign-in / password messages (command pass findings F2, F3).
import 'dart:io';

import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  test('a server refusal shows only its message', () {
    expect(
        authFailureMessage(
            const AuthApiException('Invalid login credentials', statusCode: '400', code: 'invalid_credentials')),
        'Invalid login credentials');
    expect(
        authFailureMessage(AuthWeakPasswordException(
            message: 'Password should be at least 6 characters.', statusCode: '422', reasons: ['length'])),
        'Password should be at least 6 characters.');
  });

  test('no connection reads as such', () {
    final retry = AuthRetryableFetchException(
        message: "ClientException with SocketException: Failed host lookup: 'zz.invalid' (OS Error: No such host)");
    expect(authFailureMessage(retry), cantReachServerMessage);
    expect(authFailureMessage(const SocketException('Failed host lookup')), cantReachServerMessage);
    expect(cantReachServerMessage, "can't reach the server. Check the connection, or sign in offline on your own device.");
  });

  test('anything else keeps its text, without the exception type', () {
    expect(authFailureMessage(Exception('boom')), 'boom');
    expect(authFailureMessage(StateError('odd')), 'Bad state: odd');
    expect(authFailureMessage('plain'), 'plain');
  });

  test('an Edge Function refusal shows the server\'s error text', () {
    expect(
        edgeFunctionErrorMessage(const FunctionException(
            status: 403, details: {'error': 'Bootstrap already completed for this project'}, reasonPhrase: 'Forbidden')),
        'Bootstrap already completed for this project');
    expect(edgeFunctionErrorMessage(const FunctionException(status: 500, details: 'boom')), 'boom');
    expect(edgeFunctionErrorMessage(const FunctionException(status: 502, reasonPhrase: 'Bad Gateway')), 'Bad Gateway');
    expect(edgeFunctionErrorMessage(const FunctionException(status: 503)), 'server error 503');
    expect(edgeFunctionErrorMessage(const SocketException('Failed host lookup')), cantReachServerMessage);
  });

  test('session messages name no console command', () {
    for (final m in [notSignedInMessage, needsOnlineSignInMessage, mustChangePasswordMessage]) {
      expect(m, isNot(contains('<')));
      expect(m, isNot(contains('sign-in ')));
      expect(m, isNot(contains('change-password')));
    }
    expect(notSignedInMessage, startsWith('Not signed in.'));
    expect(needsOnlineSignInMessage, startsWith('This needs an online sign-in.'));
  });
}
