import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jmap_dart_client/http/http_client.dart';
import 'package:rule_filter/sieve/sieve_account_capability.dart';
import 'package:tmail_ui_user/features/manage_account/data/datasource/rule_filter_datasource.dart';
import 'package:tmail_ui_user/features/manage_account/data/datasource_impl/rule_filter_datasource_impl.dart';
import 'package:tmail_ui_user/features/manage_account/data/datasource_impl/sieve_rule_filter_datasource_impl.dart';
import 'package:tmail_ui_user/features/manage_account/data/network/rule_filter_api.dart';
import 'package:tmail_ui_user/features/manage_account/data/network/sieve_rule_filter_api.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_backend.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/email_rules/bindings/email_rules_interactor_bindings.dart';
import 'package:tmail_ui_user/main/exceptions/thrower/remote_exception_thrower.dart';

void main() {
  setUp(() {
    final httpClient = HttpClient(Dio());
    Get.put(RuleFilterAPI(httpClient));
    Get.put(SieveRuleFilterAPI(httpClient));
    Get.put(RemoteExceptionThrower());
  });

  tearDown(Get.reset);

  test('switching backend replaces the data source', () {
    EmailRulesInteractorBindings(backend: EmailRulesBackend.linagora).dependencies();
    expect(Get.find<RuleFilterDataSource>(), isA<RuleFilterDataSourceImpl>());

    EmailRulesInteractorBindings(
      backend: EmailRulesBackend.sieve,
      sieveCapability: const SieveAccountCapability(sieveExtensions: {'fileinto'}),
    ).dependencies();
    expect(Get.find<RuleFilterDataSource>(), isA<SieveRuleFilterDataSourceImpl>());
  });

  test('the same backend and capability keep the instance (and its snapshot)', () {
    const capability = SieveAccountCapability(sieveExtensions: {'fileinto'});
    EmailRulesInteractorBindings(backend: EmailRulesBackend.sieve, sieveCapability: capability)
        .dependencies();
    final first = Get.find<RuleFilterDataSource>();

    EmailRulesInteractorBindings(backend: EmailRulesBackend.sieve, sieveCapability: capability)
        .dependencies();
    expect(identical(Get.find<RuleFilterDataSource>(), first), isTrue);
  });
}
