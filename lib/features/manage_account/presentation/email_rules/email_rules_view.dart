import 'package:core/presentation/utils/theme_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tmail_ui_user/features/base/mixin/app_loader_mixin.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/base/setting_detail_view_builder.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/email_rules_controller.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/widgets/add_rule_button_widget.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/widgets/count_name_of_rules_widget.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/widgets/email_rules_status_banner.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/widgets/list_email_rules_widget.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/widgets/no_rules_widget.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/menu/settings_utils.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/model/account_menu_item.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/model/email_rule_action_type.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/widgets/setting_explanation_widget.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/widgets/setting_header_widget.dart';

class EmailRulesView extends GetWidget<EmailRulesController>
    with AppLoaderMixin {
  const EmailRulesView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDesktop = controller.responsiveUtils.isDesktop(context);

    return SettingDetailViewBuilder(
      responsiveUtils: controller.responsiveUtils,
      child: Container(
        color: SettingsUtils.getContentBackgroundColor(
          context,
          controller.responsiveUtils,
        ),
        decoration: SettingsUtils.getBoxDecorationForContent(
          context,
          controller.responsiveUtils,
        ),
        width: double.infinity,
        padding: isDesktop
            ? const EdgeInsetsDirectional.only(
                start: 30,
                end: 30,
                top: 22,
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDesktop) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SettingHeaderWidget(
                      menuItem: AccountMenuItem.emailRules,
                      textStyle: ThemeUtils.textStyleInter600().copyWith(
                        color: Colors.black.withValues(alpha: 0.9),
                      ),
                      padding: const EdgeInsetsDirectional.only(end: 16),
                    ),
                  ),
                  Obx(
                    () => controller.isReadOnly
                        ? const SizedBox.shrink()
                        : AddRuleButtonWidget(
                            imagePaths: controller.imagePaths,
                            margin: const EdgeInsetsDirectional.only(
                              start: 169,
                              top: 24,
                              end: 57,
                            ),
                            onAddRuleAction: controller.goToCreateNewRule,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ] else ...[
              const SettingExplanationWidget(
                menuItem: AccountMenuItem.emailRules,
                padding: EdgeInsetsDirectional.symmetric(horizontal: 16),
                isCenter: true,
                textAlign: TextAlign.center,
              ),
              Obx(
                () => controller.isReadOnly
                    ? const SizedBox.shrink()
                    : Center(
                        child: AddRuleButtonWidget(
                          imagePaths: controller.imagePaths,
                          margin: const EdgeInsetsDirectional.only(
                            top: 24,
                            bottom: 16,
                          ),
                          minWidth: 230,
                          onAddRuleAction: controller.goToCreateNewRule,
                        ),
                      ),
              ),
            ],
            Obx(
              () => EmailRulesStatusBanner(
                imagePaths: controller.imagePaths,
                status: controller.emailRulesStatus.value,
                isActivating: controller.isUpdatingRules.value,
                onActivate: controller.activateRules,
                margin: EdgeInsetsDirectional.only(
                  start: isDesktop ? 0 : 16,
                  end: isDesktop ? 0 : 16,
                  top: 16,
                ),
              ),
            ),
            Obx(
              () => CountNameOfRulesWidget(
                countRules: controller.listEmailRule.length,
                hint: controller.isSieveBackend &&
                        controller.listEmailRule.length > 1
                    ? AppLocalizations.of(context).emailRulesOrderHint
                    : null,
                margin: EdgeInsetsDirectional.only(
                  start: isDesktop ? 0 : 16,
                  top: 24,
                ),
              ),
            ),
            Obx(
              () => controller.isLoading
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: loadingWidget,
                    )
                  : const SizedBox.shrink(),
            ),
            Obx(() {
              if (controller.listEmailRule.isEmpty) {
                if (controller.isLoading || controller.isReadOnly) {
                  // A read-only script has rules the webmail cannot show;
                  // "no rules yet" would be wrong.
                  return const SizedBox.shrink();
                } else {
                  return NoRulesWidget(
                    imagePaths: controller.imagePaths,
                    responsiveUtils: controller.responsiveUtils,
                    onAddRuleAction: controller.goToCreateNewRule,
                  );
                }
              } else {
                return Expanded(
                  child: ListEmailRulesWidget(
                    listEmailRule: controller.listEmailRule,
                    showOrderingControls: controller.isSieveBackend &&
                        controller.emailRulesStatus.value?.isReadOnly != true,
                    onToggleEmailRuleAction: controller.toggleRule,
                    onMoveUpEmailRuleAction: (rule) =>
                        controller.moveRule(rule, -1),
                    onMoveDownEmailRuleAction: (rule) =>
                        controller.moveRule(rule, 1),
                    imagePaths: controller.imagePaths,
                    responsiveUtils: controller.responsiveUtils,
                    onDeleteEmailRuleAction: (rule) =>
                      controller.handleRuleFilterActionType(
                        context,
                        rule,
                        EmailRuleActionType.delete,
                      ),
                    onEditEmailRuleAction: (rule) =>
                      controller.handleRuleFilterActionType(
                        context,
                        rule,
                        EmailRuleActionType.edit,
                      ),
                    onMoreEmailRuleAction: (rule) =>
                      controller.openEditRuleMenuAction(
                        context,
                        rule,
                      ),
                  ),
                );
              }
            }),
          ],
        ),
      ),
    );
  }
}
