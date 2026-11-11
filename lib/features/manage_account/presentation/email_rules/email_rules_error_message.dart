import 'package:rule_filter/sieve/sieve_rules_codec.dart';
import 'package:tmail_ui_user/features/manage_account/domain/exceptions/sieve_rules_exceptions.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

/// User-facing message for failures specific to the Sieve rules backend.
/// Returns `null` for any other error, which keeps the generic handling.
abstract final class EmailRulesErrorMessage {
  static String? of(AppLocalizations appLocalizations, dynamic exception) {
    return switch (exception) {
      SieveRulesConflictException() => appLocalizations.emailRulesConflictError,
      SieveRulesReadOnlyException(reason: EmailRulesReadOnlyReason.modifiedExternally) =>
        appLocalizations.emailRulesReadOnlyModified,
      SieveRulesReadOnlyException(reason: EmailRulesReadOnlyReason.nameConflict) =>
        appLocalizations.emailRulesReadOnlyNameConflict(managedSieveScriptName),
      SieveScriptRejectedException(:final type, :final description) =>
        appLocalizations.emailRulesScriptRejected(
          description?.isNotEmpty == true ? '$description ($type)' : type,
        ),
      SieveScriptTooLargeException() => appLocalizations.emailRulesTooLarge,
      SieveRulesReadException() => appLocalizations.emailRulesReadFailed,
      SieveRulesVerificationException() =>
        appLocalizations.emailRulesVerificationFailed,
      SieveExtensionNotSupportedException(:final missingExtensions) =>
        appLocalizations.emailRulesExtensionUnsupported(
          missingExtensions.join(', '),
        ),
      SieveRuleNotRepresentableException(:final ruleName, :final reason) =>
        appLocalizations.emailRulesScriptRejected('$ruleName: $reason'),
      _ => null,
    };
  }
}
