import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:core/utils/app_logger.dart';
import 'package:core/utils/platform_info.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/base/base_controller.dart';
import 'package:tmail_ui_user/features/base/mixin/message_dialog_action_manager.dart';
import 'package:tmail_ui_user/features/manage_account/domain/exceptions/sieve_rules_exceptions.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/create_new_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/delete_email_rule_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/edit_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';
import 'package:tmail_ui_user/features/manage_account/domain/state/create_new_rule_filter_state.dart';
import 'package:tmail_ui_user/features/manage_account/domain/state/delete_email_rule_state.dart';
import 'package:tmail_ui_user/features/manage_account/domain/state/edit_email_rule_filter_state.dart';
import 'package:tmail_ui_user/features/manage_account/domain/state/get_all_rules_state.dart';
import 'package:tmail_ui_user/features/manage_account/domain/state/update_email_rules_state.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/create_new_email_rule_filter_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/delete_email_rule_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/edit_email_rule_filter_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/get_all_rules_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/update_email_rules_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/email_rules_error_message.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/manage_account_dashboard_controller.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/model/context_item_email_rule_type_action.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/model/email_rule_action_type.dart';
import 'package:tmail_ui_user/features/rules_filter_creator/presentation/model/creator_action_type.dart';
import 'package:tmail_ui_user/features/rules_filter_creator/presentation/model/rules_filter_creator_arguments.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/routes/app_routes.dart';
import 'package:tmail_ui_user/main/routes/dialog_router.dart';
import 'package:tmail_ui_user/main/routes/route_navigation.dart';

class EmailRulesController extends BaseController {

  GetAllRulesInteractor? _getAllRulesInteractor;
  DeleteEmailRuleInteractor? _deleteEmailRuleInteractor;
  CreateNewEmailRuleFilterInteractor? _createNewEmailRuleFilterInteractor;
  EditEmailRuleFilterInteractor? _editEmailRuleFilterInteractor;
  UpdateEmailRulesInteractor? _updateEmailRulesInteractor;

  final _accountDashBoardController = Get.find<ManageAccountDashBoardController>();

  final listEmailRule = <TMailRule>[].obs;

  /// Server-side state reported by the Sieve backend (`null` for Linagora).
  final emailRulesStatus = Rxn<EmailRulesStatus>();

  final isUpdatingRules = false.obs;

  bool get isReadOnly => emailRulesStatus.value?.isReadOnly == true;

  bool get isSieveBackend =>
      _accountDashBoardController.emailRulesBackend.isSieve;

  bool get isLoading => viewState.value.fold(
    (failure) => false,
    (success) => success is GettingAllRules,
  );

  @override
  void onInit() {
    super.onInit();
    try {
      _getAllRulesInteractor = Get.find<GetAllRulesInteractor>();
      _deleteEmailRuleInteractor = Get.find<DeleteEmailRuleInteractor>();
      _createNewEmailRuleFilterInteractor = Get.find<CreateNewEmailRuleFilterInteractor>();
      _editEmailRuleFilterInteractor = Get.find<EditEmailRuleFilterInteractor>();
      _updateEmailRulesInteractor = Get.find<UpdateEmailRulesInteractor>();
    } catch (e) {
      logWarning('EmailRulesController::onInit(): ${e.toString()}');
    }
  }

  @override
  void onReady() {
    _getAllRules();
    super.onReady();
  }

  @override
  void handleSuccessViewState(Success success) {
    if (success is GetAllRulesSuccess) {
      listEmailRule.value = success.rules ?? <TMailRule>[];
      emailRulesStatus.value = success.status;
    } else if (success is UpdateEmailRulesSuccess) {
      _handleUpdateEmailRulesSuccess(success);
    } else if (success is DeleteEmailRuleSuccess) {
      _handleDeleteEmailRuleSuccess(success);
    } else if (success is CreateNewRuleFilterSuccess) {
      _createNewRuleFilterSuccess(success);
    } else if (success is EditEmailRuleFilterSuccess) {
      _editEmailRuleFilterSuccess(success);
    } else {
      super.handleSuccessViewState(success);
    }
  }

  @override
  void handleFailureViewState(Failure failure) {
    if (failure is GetAllRulesFailure) {
      listEmailRule.clear();
      _showRulesError(failure.exception);
    } else if (failure is CreateNewRuleFilterFailure ||
        failure is EditEmailRuleFilterFailure ||
        failure is DeleteEmailRuleFailure ||
        failure is UpdateEmailRulesFailure) {
      isUpdatingRules.value = false;
      final exception = (failure as FeatureFailure).exception;
      if (!_showRulesError(exception)) {
        super.handleFailureViewState(failure);
      }
      if (exception is SieveRulesConflictException ||
          exception is SieveRulesVerificationException ||
          exception is SieveRulesReadOnlyException) {
        // Show what the server holds now instead of the stale local list.
        _getAllRules();
      }
    } else {
      super.handleFailureViewState(failure);
    }
  }

  /// Shows the specific message of a Sieve failure. Returns false for other
  /// errors, which keep the generic handling.
  bool _showRulesError(dynamic exception) {
    if (currentOverlayContext == null || currentContext == null) return false;
    final message = EmailRulesErrorMessage.of(
      AppLocalizations.of(currentContext!),
      exception,
    );
    if (message == null) return false;
    appToast.showToastErrorMessage(currentOverlayContext!, message);
    return true;
  }

  bool _blockIfReadOnly() {
    final status = emailRulesStatus.value;
    if (status?.isReadOnly != true) return false;
    _showRulesError(SieveRulesReadOnlyException(status!.readOnlyReason!));
    return true;
  }

  /// Toast after a write: a Sieve script that was saved but is not running
  /// must not look like a plain success.
  void _showSavedMessage(String successMessage, EmailRulesStatus? status) {
    if (currentOverlayContext == null || currentContext == null) return;
    if (status != null && !status.isActive) {
      appToast.showToastWarningMessage(
        currentOverlayContext!,
        AppLocalizations.of(currentContext!).emailRulesSavedButInactive,
      );
    } else {
      appToast.showToastSuccessMessage(currentOverlayContext!, successMessage);
    }
  }

  void moveRule(TMailRule rule, int offset) {
    final index = _indexOf(rule);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= listEmailRule.length) return;
    final rules = List<TMailRule>.of(listEmailRule);
    final moved = rules.removeAt(index);
    rules.insert(target, moved);
    _updateRules(rules);
  }

  void toggleRule(TMailRule rule) {
    final index = _indexOf(rule);
    if (index < 0) return;
    final rules = List<TMailRule>.of(listEmailRule);
    rules[index] = rules[index].copyWith(isEnabled: !rules[index].isEnabled);
    _updateRules(rules);
  }

  /// Writes the same rules again; the backend activates the script when no
  /// other script is active.
  void activateRules() => _updateRules(List<TMailRule>.of(listEmailRule));

  int _indexOf(TMailRule rule) {
    final index = int.tryParse(rule.id?.id.value ?? '');
    if (index != null && index >= 0 && index < listEmailRule.length) {
      return index;
    }
    return listEmailRule.indexOf(rule);
  }

  void _updateRules(List<TMailRule> rules) {
    final accountId = _accountDashBoardController.accountId.value;
    if (accountId == null ||
        _updateEmailRulesInteractor == null ||
        isUpdatingRules.value ||
        _blockIfReadOnly()) {
      return;
    }
    isUpdatingRules.value = true;
    consumeState(_updateEmailRulesInteractor!.execute(
      accountId,
      rules,
      currentRules: List<TMailRule>.of(listEmailRule),
    ));
  }

  void _handleUpdateEmailRulesSuccess(UpdateEmailRulesSuccess success) {
    isUpdatingRules.value = false;
    listEmailRule.value = success.rules;
    emailRulesStatus.value = success.status;
    if (currentContext != null) {
      _showSavedMessage(
        AppLocalizations.of(currentContext!).emailRulesUpdated,
        success.status,
      );
    }
  }

  Future<void> goToCreateNewRule() async {
    if (_blockIfReadOnly()) return;
    final accountId = _accountDashBoardController.accountId.value;
    final session = _accountDashBoardController.sessionCurrent;
    if (accountId != null && session != null) {
      final arguments = RulesFilterCreatorArguments(accountId, session);

      final newRuleFilterRequest = PlatformInfo.isWeb
        ? await DialogRouter().pushGeneralDialog(routeName: AppRoutes.rulesFilterCreator, arguments: arguments)
        : await push(AppRoutes.rulesFilterCreator, arguments: arguments);

      if (newRuleFilterRequest is CreateNewEmailRuleFilterRequest) {
        _createNewRuleFilterAction(accountId, newRuleFilterRequest);
      }
    }
  }

  void _createNewRuleFilterAction(
      AccountId accountId,
      CreateNewEmailRuleFilterRequest ruleFilterRequest
  ) async {
    if (_createNewEmailRuleFilterInteractor != null) {
      consumeState(_createNewEmailRuleFilterInteractor!.execute(accountId, ruleFilterRequest));
    }
  }

  void _createNewRuleFilterSuccess(CreateNewRuleFilterSuccess success) {
    if (success.newListRules.isNotEmpty == true) {
      if (currentContext != null) {
        _showSavedMessage(
          AppLocalizations.of(currentContext!).newFilterWasCreated,
          success.status,
        );
      }
      listEmailRule.value = success.newListRules;
      emailRulesStatus.value = success.status ?? emailRulesStatus.value;
      listEmailRule.refresh();
    }
  }

  void editEmailRule(BuildContext context, TMailRule rule) async {
    if (_blockIfReadOnly()) return;
    final accountId = _accountDashBoardController.accountId.value;
    final session = _accountDashBoardController.sessionCurrent;
    if (accountId != null && session != null) {
      final arguments = RulesFilterCreatorArguments(
        accountId,
        session,
        actionType: CreatorActionType.edit,
        tMailRule: rule);

      final newRuleFilterRequest = PlatformInfo.isWeb
        ? await DialogRouter().pushGeneralDialog(routeName: AppRoutes.rulesFilterCreator, arguments: arguments)
        : await push(AppRoutes.rulesFilterCreator, arguments: arguments);

      if (newRuleFilterRequest is EditEmailRuleFilterRequest) {
        _editEmailRuleFilterAction(accountId, newRuleFilterRequest);
      }
    }
  }

  void _editEmailRuleFilterAction(
      AccountId accountId,
      EditEmailRuleFilterRequest ruleFilterRequest
  ) {
    if (_editEmailRuleFilterInteractor != null) {
      consumeState(_editEmailRuleFilterInteractor!.execute(accountId, ruleFilterRequest));
    }
  }

  void _editEmailRuleFilterSuccess(EditEmailRuleFilterSuccess success) {
    if (success.listRulesUpdated.isNotEmpty == true) {
      if (currentContext != null) {
        _showSavedMessage(
          AppLocalizations.of(currentContext!).yourFilterHasBeenUpdated,
          success.status,
        );
      }
      listEmailRule.value = success.listRulesUpdated;
      emailRulesStatus.value = success.status ?? emailRulesStatus.value;
      listEmailRule.refresh();
    }
  }

  void _deleteEmailRule(BuildContext context, TMailRule emailRule) {
    if (_blockIfReadOnly()) return;
    MessageDialogActionManager().showConfirmDialogAction(
      context,
      title: AppLocalizations.of(context).deleteEmailRule,
      AppLocalizations.of(context).messageConfirmationDialogDeleteEmailRule(emailRule.name),
      AppLocalizations.of(context).delete,
      alignCenter: true,
      cancelTitle: AppLocalizations.of(context).cancel,
      onConfirmAction: () => _handleDeleteEmailRuleAction(emailRule),
      onCloseButtonAction: popBack,
    );
  }

  void _handleDeleteEmailRuleAction(TMailRule emailRule) {
    emailRule = emailRule.withoutLegacyCondition();

    listEmailRule.value = listEmailRule
        .map((rule) => rule.withoutLegacyCondition())
        .toList();

    if (_deleteEmailRuleInteractor != null) {
      final deleteEmailRuleRequest = DeleteEmailRuleRequest(
        emailRuleDelete : emailRule,
        currentEmailRules: listEmailRule,
      );

      consumeState(_deleteEmailRuleInteractor!.execute(
        _accountDashBoardController.accountId.value!,
        deleteEmailRuleRequest));
    }
  }

  void _handleDeleteEmailRuleSuccess(DeleteEmailRuleSuccess success) {
    if (currentOverlayContext != null && currentContext != null) {
      appToast.showToastSuccessMessage(
        currentOverlayContext!,
        AppLocalizations.of(currentContext!).toastMessageDeleteEmailRuleSuccessfully);
    }

    // An empty list is a valid result: the last rule was deleted.
    listEmailRule.value = success.rules ?? <TMailRule>[];
    emailRulesStatus.value = success.status ?? emailRulesStatus.value;
  }

  void _getAllRules() {
    if (_getAllRulesInteractor != null) {
      consumeState(_getAllRulesInteractor!.execute(_accountDashBoardController.accountId.value!));
    } else {
      consumeState(Stream.value(Left(GetAllRulesFailure(null))));
    }
  }

  void openEditRuleMenuAction(BuildContext context, TMailRule rule) {
    final index = _indexOf(rule);
    final contextMenuActions = [
      EmailRuleActionType.edit,
      if (isSieveBackend) ...[
        rule.isEnabled ? EmailRuleActionType.disable : EmailRuleActionType.enable,
        if (index > 0) EmailRuleActionType.moveUp,
        if (index >= 0 && index < listEmailRule.length - 1)
          EmailRuleActionType.moveDown,
      ],
      EmailRuleActionType.delete,
    ].map((filter) {
      return ContextItemEmailRuleTypeAction(
        filter,
        AppLocalizations.of(context),
        imagePaths,
      );
    }).toList();

    openBottomSheetContextMenuAction(
      context: context,
      itemActions: contextMenuActions,
      onContextMenuActionClick: (action) {
        popBack();
        handleRuleFilterActionType(context, rule, action.action);
      },
    );
  }

  void handleRuleFilterActionType(
    BuildContext context,
    TMailRule rule,
    EmailRuleActionType actionType,
  ) {
    switch (actionType) {
      case EmailRuleActionType.edit:
        editEmailRule(context, rule);
        break;
      case EmailRuleActionType.delete:
        _deleteEmailRule(context, rule);
        break;
      case EmailRuleActionType.moveUp:
        moveRule(rule, -1);
        break;
      case EmailRuleActionType.moveDown:
        moveRule(rule, 1);
        break;
      case EmailRuleActionType.enable:
      case EmailRuleActionType.disable:
        toggleRule(rule);
        break;
      case EmailRuleActionType.add:
        break;
    }
  }
}