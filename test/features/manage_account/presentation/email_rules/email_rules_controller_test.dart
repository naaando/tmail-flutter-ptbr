import 'package:core/data/network/config/dynamic_url_interceptors.dart';
import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/app_toast.dart';
import 'package:core/presentation/utils/responsive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:rule_filter/rule_filter/rule_action.dart';
import 'package:rule_filter/rule_filter/rule_append_in.dart';
import 'package:rule_filter/rule_filter/rule_id.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:tmail_ui_user/features/caching/caching_manager.dart';
import 'package:tmail_ui_user/features/login/data/network/interceptors/authorization_interceptors.dart';
import 'package:tmail_ui_user/features/login/domain/usecases/delete_authority_oidc_interactor.dart';
import 'package:tmail_ui_user/features/login/domain/usecases/delete_credential_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/data/local/language_cache_manager.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/create_new_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/delete_email_rule_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/edit_email_rule_filter_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_backend.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';
import 'package:tmail_ui_user/features/manage_account/domain/repository/rule_filter_repository.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/create_new_email_rule_filter_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/delete_email_rule_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/edit_email_rule_filter_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/get_all_rules_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/log_out_oidc_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/update_email_rules_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/email_rules_controller.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/manage_account_dashboard_controller.dart';
import 'package:tmail_ui_user/main/bindings/network/binding_tag.dart';
import 'package:tmail_ui_user/main/utils/toast_manager.dart';
import 'package:tmail_ui_user/main/utils/twake_app_manager.dart';
import 'package:uuid/uuid.dart';

import 'email_rules_controller_test.mocks.dart';

/// Records writes and answers them like a server that accepts everything.
class _Repository implements RuleFilterRepository {
  _Repository(this.rules, this.status);

  List<TMailRule> rules;
  EmailRulesStatus? status;
  final writes = <(List<TMailRule> rules, List<TMailRule>? current)>[];

  @override
  Future<List<TMailRule>> getAllTMailRule(AccountId accountId) async => rules;

  @override
  Future<EmailRulesStatus?> getRulesStatus(AccountId accountId) async => status;

  @override
  Future<List<TMailRule>> replaceAllTMailRules(
    AccountId accountId,
    List<TMailRule> rules, {
    List<TMailRule>? currentRules,
  }) async {
    writes.add((rules, currentRules));
    return this.rules = rules;
  }

  @override
  Future<List<TMailRule>> createNewEmailRuleFilter(
          AccountId a, CreateNewEmailRuleFilterRequest r) =>
      throw UnimplementedError();

  @override
  Future<List<TMailRule>> deleteTMailRule(AccountId a, DeleteEmailRuleRequest r) =>
      throw UnimplementedError();

  @override
  Future<List<TMailRule>> editEmailRuleFilter(
          AccountId a, EditEmailRuleFilterRequest r) =>
      throw UnimplementedError();
}

TMailRule _rule(String name, {bool enabled = true}) => TMailRule(
      name: name,
      action: RuleAction(appendIn: RuleAppendIn(mailboxIds: const [])),
      isEnabled: enabled,
    );

/// The list widget gives each row its index as id.
TMailRule _row(List<TMailRule> rules, int index) =>
    rules[index].copyWith(id: RuleId(id: Id('$index')));

@GenerateNiceMocks([
  MockSpec<CachingManager>(),
  MockSpec<LanguageCacheManager>(),
  MockSpec<AuthorizationInterceptors>(),
  MockSpec<DynamicUrlInterceptors>(),
  MockSpec<DeleteCredentialInteractor>(),
  MockSpec<LogoutOidcInteractor>(),
  MockSpec<DeleteAuthorityOidcInteractor>(),
  MockSpec<AppToast>(),
  MockSpec<ResponsiveUtils>(),
  MockSpec<Uuid>(),
  MockSpec<ToastManager>(),
  MockSpec<TwakeAppManager>(),
  MockSpec<ManageAccountDashBoardController>(),
])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final accountId = AccountId(Id('acc'));
  late _Repository repository;
  late EmailRulesController controller;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() async {
    Get.testMode = true;
    Get.put<CachingManager>(MockCachingManager());
    Get.put<LanguageCacheManager>(MockLanguageCacheManager());
    final interceptors = MockAuthorizationInterceptors();
    Get.put<AuthorizationInterceptors>(interceptors);
    Get.put<AuthorizationInterceptors>(interceptors, tag: BindingTag.isolateTag);
    Get.put<DynamicUrlInterceptors>(MockDynamicUrlInterceptors());
    Get.put<DeleteCredentialInteractor>(MockDeleteCredentialInteractor());
    Get.put<LogoutOidcInteractor>(MockLogoutOidcInteractor());
    Get.put<DeleteAuthorityOidcInteractor>(MockDeleteAuthorityOidcInteractor());
    Get.put<AppToast>(MockAppToast());
    Get.put<ImagePaths>(ImagePaths());
    Get.put<ResponsiveUtils>(MockResponsiveUtils());
    Get.put<Uuid>(MockUuid());
    Get.put<ToastManager>(MockToastManager());
    Get.put<TwakeAppManager>(MockTwakeAppManager());

    final dashboard = MockManageAccountDashBoardController();
    when(dashboard.onStart).thenReturn(InternalFinalCallback<void>(callback: () {}));
    when(dashboard.onDelete).thenReturn(InternalFinalCallback<void>(callback: () {}));
    when(dashboard.accountId).thenReturn(Rxn(accountId));
    when(dashboard.emailRulesBackend).thenReturn(EmailRulesBackend.sieve);
    Get.put<ManageAccountDashBoardController>(dashboard);

    repository = _Repository(
      [_rule('A'), _rule('B'), _rule('C')],
      const EmailRulesStatus(hasManagedScript: true, isActive: true),
    );
    Get.put(GetAllRulesInteractor(repository));
    Get.put(DeleteEmailRuleInteractor(repository));
    Get.put(CreateNewEmailRuleFilterInteractor(repository));
    Get.put(EditEmailRuleFilterInteractor(repository));
    Get.put(UpdateEmailRulesInteractor(repository));

    controller = EmailRulesController();
    Get.put(controller);
    controller.onReady();
    await settle();
  });

  tearDown(Get.reset);

  List<String> names() => controller.listEmailRule.map((rule) => rule.name).toList();

  test('loads rules and server status', () {
    expect(names(), ['A', 'B', 'C']);
    expect(controller.emailRulesStatus.value?.isActive, isTrue);
    expect(controller.isSieveBackend, isTrue);
  });

  test('moving a rule sends the new order and the list it came from', () async {
    final before = List<TMailRule>.of(controller.listEmailRule);

    controller.moveRule(_row(before, 2), -1);
    await settle();

    expect(repository.writes.single.$1.map((rule) => rule.name), ['A', 'C', 'B']);
    expect(repository.writes.single.$2, before);
    expect(names(), ['A', 'C', 'B']);
  });

  test('moves past the ends are ignored', () async {
    final rules = List<TMailRule>.of(controller.listEmailRule);
    controller.moveRule(_row(rules, 0), -1);
    controller.moveRule(_row(rules, 2), 1);
    await settle();

    expect(repository.writes, isEmpty);
  });

  test('toggling flips only that rule', () async {
    controller.toggleRule(_row(controller.listEmailRule, 1));
    await settle();

    expect(
      repository.writes.single.$1.map((rule) => rule.isEnabled),
      [true, false, true],
    );
    expect(controller.listEmailRule[1].isEnabled, isFalse);
  });

  test('activating writes the same rules again', () async {
    controller.activateRules();
    await settle();

    expect(repository.writes.single.$1.map((rule) => rule.name), ['A', 'B', 'C']);
  });

  test('read-only rules are never written', () async {
    controller.emailRulesStatus.value = const EmailRulesStatus(
      hasManagedScript: true,
      isActive: true,
      readOnlyReason: EmailRulesReadOnlyReason.modifiedExternally,
    );

    controller.toggleRule(_row(controller.listEmailRule, 0));
    controller.moveRule(_row(controller.listEmailRule, 1), -1);
    controller.activateRules();
    await settle();

    expect(controller.isReadOnly, isTrue);
    expect(repository.writes, isEmpty);
  });

  test('a second change is ignored while the first is saving', () async {
    controller.toggleRule(_row(controller.listEmailRule, 0));
    controller.toggleRule(_row(controller.listEmailRule, 1));
    await settle();

    expect(repository.writes, hasLength(1));
  });
}
