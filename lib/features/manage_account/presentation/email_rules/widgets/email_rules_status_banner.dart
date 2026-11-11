import 'package:core/presentation/resources/image_paths.dart';
import 'package:flutter/material.dart';
import 'package:rule_filter/sieve/sieve_rules_codec.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/widgets/email_rules_notice_banner.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

/// Explains why the Sieve rules are not running or cannot be edited. Shows
/// nothing when the rules are active (or the backend reports no status).
class EmailRulesStatusBanner extends StatelessWidget {
  final ImagePaths imagePaths;
  final EmailRulesStatus? status;
  final VoidCallback onActivate;
  final bool isActivating;
  final EdgeInsetsGeometry? margin;

  const EmailRulesStatusBanner({
    super.key,
    required this.imagePaths,
    required this.status,
    required this.onActivate,
    this.isActivating = false,
    this.margin,
  });

  static String? messageOf(
    AppLocalizations appLocalizations,
    EmailRulesStatus? status,
  ) {
    if (status == null) return null;
    switch (status.readOnlyReason) {
      case EmailRulesReadOnlyReason.modifiedExternally:
        return appLocalizations.emailRulesReadOnlyModified;
      case EmailRulesReadOnlyReason.nameConflict:
        return appLocalizations.emailRulesReadOnlyNameConflict(
          managedSieveScriptName,
        );
      case null:
        break;
    }
    if (status.blockedByVacation) {
      return status.hasManagedScript
          ? appLocalizations.emailRulesBlockedByVacation
          : appLocalizations.emailRulesNewBlockedByVacation;
    }
    if (status.isBlocked) {
      return status.hasManagedScript
          ? appLocalizations.emailRulesBlockedByOtherScript(
              status.blockingScriptName!,
            )
          : appLocalizations.emailRulesNewBlockedByOtherScript(
              status.blockingScriptName!,
            );
    }
    if (status.canActivate) {
      return appLocalizations.emailRulesStatusInactive;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final message = messageOf(appLocalizations, status);
    if (message == null) return const SizedBox.shrink();

    final canActivate = status?.canActivate == true;
    return EmailRulesNoticeBanner(
      key: const ValueKey('email_rules_status_banner'),
      imagePaths: imagePaths,
      message: message,
      isWarning: true,
      actionLabel: canActivate ? appLocalizations.emailRulesActivate : null,
      onAction: canActivate ? onActivate : null,
      isActionLoading: isActivating,
      margin: margin,
    );
  }
}
