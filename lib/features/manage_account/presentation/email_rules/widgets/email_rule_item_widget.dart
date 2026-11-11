import 'package:core/presentation/extensions/color_extension.dart';
import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/responsive_utils.dart';
import 'package:core/presentation/utils/theme_utils.dart';
import 'package:core/presentation/views/button/tmail_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/base/model/ui_keys.dart';
import 'package:tmail_ui_user/features/base/widget/default_switch_icon_widget.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/extensions/tmail_rule_extension.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

typedef OnEditEmailRuleAction = Function(TMailRule rule);
typedef OnDeleteEmailRuleAction = Function(TMailRule rule);
typedef OnMoreEmailRuleAction = Function(TMailRule rule);
typedef OnToggleEmailRuleAction = Function(TMailRule rule);
typedef OnMoveEmailRuleAction = Function(TMailRule rule);

class EmailRulesItemWidget extends StatelessWidget {
  final ImagePaths imagePaths;
  final ResponsiveUtils responsiveUtils;
  final TMailRule rule;
  final OnEditEmailRuleAction? onEditEmailRuleAction;
  final OnDeleteEmailRuleAction? onDeleteEmailRuleAction;
  final OnMoreEmailRuleAction? onMoreEmailRuleAction;

  /// Enable/disable and reorder controls. Only backends that keep an
  /// explicit order and per-rule state (Sieve) show them.
  final bool showOrderingControls;
  final bool canMoveUp;
  final bool canMoveDown;

  /// The rule files into a folder that no longer exists.
  final bool hasMissingMailbox;
  final OnToggleEmailRuleAction? onToggleEmailRuleAction;
  final OnMoveEmailRuleAction? onMoveUpEmailRuleAction;
  final OnMoveEmailRuleAction? onMoveDownEmailRuleAction;

  const EmailRulesItemWidget({
    Key? key,
    required this.imagePaths,
    required this.responsiveUtils,
    required this.rule,
    this.onEditEmailRuleAction,
    this.onDeleteEmailRuleAction,
    this.onMoreEmailRuleAction,
    this.showOrderingControls = false,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.hasMissingMailbox = false,
    this.onToggleEmailRuleAction,
    this.onMoveUpEmailRuleAction,
    this.onMoveDownEmailRuleAction,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isMobile = responsiveUtils.isMobile(context);
    final appLocalizations = AppLocalizations.of(context);
    final nameColor = rule.isEnabled ? Colors.black : AppColor.steelGray400;
    final preview = [
      if (!rule.isEnabled) appLocalizations.ruleDisabled,
      if (hasMissingMailbox) appLocalizations.emailRuleMissingFolder,
      rule.getPreview(appLocalizations),
    ].join(' · ');

    return Container(
      decoration: const BoxDecoration(
        color: AppColor.lightGrayF9FAFB,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      height: 72,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 32),
      margin: const EdgeInsetsDirectional.only(top: 8),
      child: Row(
        children: [
          if (showOrderingControls)
            _ToggleRuleButton(
              key: ValueKey('${UiKeys.toggleEmailRuleButton}_${rule.name}'),
              imagePaths: imagePaths,
              isEnabled: rule.isEnabled,
              tooltip: rule.isEnabled
                  ? appLocalizations.disableRule
                  : appLocalizations.enableRule,
              onTap: () => onToggleEmailRuleAction?.call(rule),
            ),
          if (!isMobile) ...[
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: context.width / 2),
              child: Text(
                rule.name,
                style: ThemeUtils.textStyleBodyBody3(
                  color: nameColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColor.gray49454F.withValues(alpha: 0.08),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(16),
                        ),
                      ),
                      margin: const EdgeInsetsDirectional.symmetric(
                        horizontal: 24,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 12,
                      ),
                      child: Text(
                        preview,
                        style: ThemeUtils.textStyleBodyBody3(
                          color: nameColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                ],
              ),
            ),
            if (showOrderingControls) ...[
              _MoveRuleButton(
                key: ValueKey('${UiKeys.moveUpEmailRuleButton}_${rule.name}'),
                icon: imagePaths.icChevronUp,
                tooltip: appLocalizations.moveRuleUp,
                onTap: canMoveUp
                    ? () => onMoveUpEmailRuleAction?.call(rule)
                    : null,
              ),
              _MoveRuleButton(
                key: ValueKey('${UiKeys.moveDownEmailRuleButton}_${rule.name}'),
                icon: imagePaths.icChevronDown,
                tooltip: appLocalizations.moveRuleDown,
                onTap: canMoveDown
                    ? () => onMoveDownEmailRuleAction?.call(rule)
                    : null,
              ),
            ],
            TMailButtonWidget.fromIcon(
              key: ValueKey('${UiKeys.editEmailRuleButton}_${rule.name}'),
              icon: imagePaths.icEdit,
              iconSize: 20,
              iconColor: AppColor.steelGrayA540,
              backgroundColor: Colors.transparent,
              tooltipMessage: appLocalizations.editRule,
              margin: const EdgeInsetsDirectional.only(end: 12),
              onTapActionCallback: () => onEditEmailRuleAction?.call(rule),
            ),
            TMailButtonWidget.fromIcon(
              icon: imagePaths.icDeleteComposer,
              iconSize: 20,
              iconColor: AppColor.steelGrayA540,
              backgroundColor: Colors.transparent,
              tooltipMessage: appLocalizations.deleteRule,
              onTapActionCallback: () => onDeleteEmailRuleAction?.call(rule),
            ),
          ] else ...[
            Expanded(
              child: Text(
                rule.name,
                style: ThemeUtils.textStyleBodyBody3(
                  color: nameColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TMailButtonWidget.fromIcon(
              key: ValueKey('${UiKeys.moreEmailRuleButton}_${rule.name}'),
              icon: imagePaths.icMoreVertical,
              iconSize: 20,
              iconColor: AppColor.steelGrayA540,
              backgroundColor: Colors.transparent,
              onTapActionCallback: () => onMoreEmailRuleAction?.call(rule),
            ),
          ],
        ],
      ),
    );
  }
}

/// Switch that enables or disables a single rule without opening the editor.
class _ToggleRuleButton extends StatelessWidget {
  final ImagePaths imagePaths;
  final bool isEnabled;
  final String tooltip;
  final VoidCallback onTap;

  const _ToggleRuleButton({
    super.key,
    required this.imagePaths,
    required this.isEnabled,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 16),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          toggled: isEnabled,
          button: true,
          label: tooltip,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            onTap: onTap,
            child: DefaultSwitchIconWidget(
              imagePaths: imagePaths,
              isEnabled: isEnabled,
            ),
          ),
        ),
      ),
    );
  }
}

class _MoveRuleButton extends StatelessWidget {
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _MoveRuleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TMailButtonWidget.fromIcon(
      icon: icon,
      iconSize: 20,
      iconColor: onTap == null ? AppColor.steelGray200 : AppColor.steelGrayA540,
      backgroundColor: Colors.transparent,
      tooltipMessage: tooltip,
      margin: const EdgeInsetsDirectional.only(end: 4),
      onTapActionCallback: onTap,
    );
  }
}
