import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';
import 'package:rule_filter/sieve/sieve_account_capability.dart';
import 'package:rule_filter/sieve/sieve_rules_codec.dart';

/// Shape of the session announced by Stalwart v0.16 (trimmed).
Map<String, dynamic> _stalwartSession() => {
      'capabilities': {
        'urn:ietf:params:jmap:core': {
          'maxSizeUpload': 50000000,
          'maxConcurrentUpload': 4,
          'maxSizeRequest': 10000000,
          'maxConcurrentRequests': 4,
          'maxCallsInRequest': 16,
          'maxObjectsInGet': 500,
          'maxObjectsInSet': 500,
          'collationAlgorithms': ['i;unicode-casemap'],
        },
        'urn:ietf:params:jmap:sieve': {'implementation': 'Stalwart v1.0.0'},
      },
      'accounts': {
        'b': {
          'name': 'bob@qa.test',
          'isPersonal': true,
          'isReadOnly': false,
          'accountCapabilities': {
            'urn:ietf:params:jmap:sieve': {
              'maxSizeScriptName': 512,
              'maxSizeScript': 102400,
              'maxNumberScripts': 100,
              'maxNumberRedirects': 1,
              'sieveExtensions': ['fileinto', 'mailbox', 'mailboxid', 'imap4flags'],
              'notificationMethods': ['mailto'],
              'externalLists': null,
            },
          },
        },
      },
      'primaryAccounts': {'urn:ietf:params:jmap:sieve': 'b'},
      'username': 'bob@qa.test',
      'apiUrl': 'https://mail.qa.test/jmap/',
      'downloadUrl': 'https://mail.qa.test/jmap/download/{accountId}/{blobId}/{name}?accept={type}',
      'uploadUrl': 'https://mail.qa.test/jmap/upload/{accountId}/',
      'eventSourceUrl': 'https://mail.qa.test/jmap/eventsource/',
      'state': 's1',
    };

void main() {
  test('reads limits from the account and implementation from the session', () {
    final session = Session.fromJson(_stalwartSession());
    final capability =
        SieveAccountCapability.fromSession(session, AccountId(Id('b')))!;

    expect(capability.maxSizeScript, 102400);
    expect(capability.maxNumberScripts, 100);
    expect(capability.implementation, 'Stalwart v1.0.0');
    expect(capability.supportsExtension('mailboxid'), isTrue);
    expect(
      const SieveRulesCodec().chooseComparator(capability),
      unicodeCaseMapComparator,
    );
  });

  test('returns null when the account does not announce Sieve', () {
    final json = _stalwartSession();
    (json['accounts'] as Map)['b']['accountCapabilities'] = <String, dynamic>{};
    final session = Session.fromJson(json);

    expect(SieveAccountCapability.fromSession(session, AccountId(Id('b'))), isNull);
  });
}
