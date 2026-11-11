import 'package:dio/dio.dart';

/// Requests RFC 8621 compliant header forms for headers the JMAP client asks
/// for `asText`, and maps the answers back so the rest of the app is unchanged.
///
/// RFC 8621 section 4.1.2 only allows `asText` for headers that are not
/// defined by RFC 5322 or RFC 2369 (besides Subject, Comments, Keywords and
/// List-Id). `jmap_dart_client` asks for `List-Unsubscribe`, `List-Post` and
/// `Return-Path` as text. Apache James accepts it, but Stalwart 1.x answers
/// `invalidArguments` to the whole `Email/get`, which leaves the mailbox list
/// empty. `asRaw` is valid for every header and is still a string, so the
/// values keep their type; callers already trim them.
class JmapHeaderFormInterceptor extends Interceptor {
  static const Map<String, String> requestedToCompliant = {
    'header:List-Unsubscribe:asText': 'header:List-Unsubscribe:asRaw',
    'header:List-Post:asText': 'header:List-Post:asRaw',
    'header:Return-Path:asText': 'header:Return-Path:asRaw',
  };

  static final Map<String, String> _compliantToRequested = {
    for (final entry in requestedToCompliant.entries) entry.value: entry.key,
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final data = options.data;
    if (data is Map<String, dynamic> && data['methodCalls'] is List) {
      for (final call in data['methodCalls'] as List) {
        if (call is List && call.length > 1 && call[1] is Map) {
          _rewriteProperties(call[1] as Map);
        }
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final data = response.data;
    if (data is Map && data['methodResponses'] is List) {
      for (final methodResponse in data['methodResponses'] as List) {
        if (methodResponse is List &&
            methodResponse.length > 1 &&
            methodResponse[0] == 'Email/get' &&
            methodResponse[1] is Map) {
          final list = (methodResponse[1] as Map)['list'];
          if (list is List) {
            for (final email in list) {
              if (email is Map) _restoreKeys(email);
            }
          }
        }
      }
    }
    handler.next(response);
  }

  static void _rewriteProperties(Map arguments) {
    for (final key in const ['properties', 'bodyProperties']) {
      final properties = arguments[key];
      if (properties is List) {
        arguments[key] = properties
            .map((property) => requestedToCompliant[property] ?? property)
            .toList();
      }
    }
  }

  static void _restoreKeys(Map email) {
    for (final entry in _compliantToRequested.entries) {
      if (email.containsKey(entry.key)) {
        email[entry.value] = email.remove(entry.key);
      }
    }
  }
}
