// lib/ui/common/error_display.dart
// The one rule for showing failures (docs/handoff/screens/common.md, Error
// display): a ViewModelException's message is written for the user and is
// shown as is; anything else is shown as unexpectedErrorMessage and its
// detail goes to the log only.
import 'package:flutter/material.dart';

import '../../core/models/messages.dart';
import '../../viewmodels/viewmodel_exception.dart';

/// The text to show for [error]. [where] names the screen in the log line.
String errorMessageFor(Object error, {String where = 'BASA'}) {
  if (error is ViewModelException) return error.message;
  debugPrint('$where: $error');
  return unexpectedErrorMessage;
}

/// Shows [error] in a snack bar, by the same rule.
void showErrorSnackBar(BuildContext context, Object error, {String where = 'BASA'}) {
  final colors = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: colors.errorContainer,
      content: Text(
        errorMessageFor(error, where: where),
        style: TextStyle(color: colors.onErrorContainer),
      ),
    ),
  );
}

/// A failure message in place, with an optional "Try again".
/// [message] is already user text (from [errorMessageFor] or a ViewModel's
/// returned refusal).
class ErrorMessage extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  /// Centered with padding, for a message that fills the screen body.
  final bool fill;

  const ErrorMessage({super.key, required this.message, this.onRetry, this.fill = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final box = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: colors.error, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(message, style: TextStyle(color: colors.onErrorContainer, height: 1.35)),
                if (onRetry != null) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Try again'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onErrorContainer,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (!fill) return box;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: box),
      ),
    );
  }
}
