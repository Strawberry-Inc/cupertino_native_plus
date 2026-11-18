import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the iOS side of platform views: records the params each view
/// is created with and the calls sent on each view's channel
/// (`<viewType>_<id>`).
class FakePlatformViews {
  FakePlatformViews(this._tester) {
    _messenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      _onPlatformViewsCall,
    );
  }

  final WidgetTester _tester;

  TestDefaultBinaryMessenger get _messenger =>
      _tester.binding.defaultBinaryMessenger;

  /// View type by view id.
  final Map<int, String> viewTypes = {};

  /// Creation params by view id.
  final Map<int, Map<Object?, Object?>> created = {};

  /// Calls received on each view's channel, by view id.
  final Map<int, List<MethodCall>> calls = {};

  /// While set, creating a view waits for it.
  Completer<void>? creating;

  /// While set, replies on the views' channels wait for it.
  Completer<void>? replying;

  /// While set for a method, replies to that method wait for it.
  final Map<String, Completer<void>> replyingTo = {};

  /// Methods whose calls answer with an error.
  final Set<String> failingMethods = {};

  /// Whether the views' channels answer with an error.
  bool failing = false;

  Future<Object?> _onPlatformViewsCall(MethodCall call) async {
    if (call.method != 'create') return null;
    final args = call.arguments as Map<Object?, Object?>;
    final id = args['id']! as int;
    viewTypes[id] = args['viewType']! as String;
    final params = args['params'] as Uint8List?;
    created[id] = params == null
        ? {}
        : const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(params),
              )!
              as Map<Object?, Object?>;
    calls[id] = [];
    _messenger.setMockMethodCallHandler(channel(id), (call) async {
      calls[id]!.add(call);
      await replying?.future;
      await replyingTo[call.method]?.future;
      if (failing || failingMethods.contains(call.method)) {
        throw PlatformException(code: 'failed');
      }
      return null;
    });
    await creating?.future;
    return null;
  }

  MethodChannel channel(int id) => MethodChannel('${viewTypes[id]}_$id');

  int get onlyId => created.keys.single;

  /// Sends [call] from the iOS side of view [id]. Pump to deliver it.
  void sendFromNative(int id, MethodCall call) {
    unawaited(
      _messenger.handlePlatformMessage(
        channel(id).name,
        const StandardMethodCodec().encodeMethodCall(call),
        null,
      ),
    );
  }
}
