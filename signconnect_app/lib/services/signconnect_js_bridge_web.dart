// Web-only JS interop bridge for SignConnect.
// Loaded only on the browser platform via signconnect_js_bridge.dart.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:js' as js;

class SignConnectJsBridge {
  static bool hasProperty(String name) => js.context.hasProperty(name);

  static void callMethod(String name, [List<Object?> arguments = const []]) {
    js.context.callMethod(name, arguments);
  }
}
