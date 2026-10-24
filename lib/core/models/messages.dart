// lib/core/models/messages.dart
// Fixed user-facing texts a screen needs (spec 2026-10-24-vm-completeness):
// a ViewModelException's message is shown as is; any other exception is shown
// as unexpectedErrorMessage and logged. Re-exported so screens never import
// core/services/.
export '../services/auth_messages.dart' show unexpectedErrorMessage, notSignedInMessage;
