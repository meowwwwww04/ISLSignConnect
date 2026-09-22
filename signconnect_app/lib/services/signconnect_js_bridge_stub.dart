// No-op JS bridge for non-web platforms (VM tests, Android, iOS, desktop).

class SignConnectJsBridge {
  static bool hasProperty(String name) => false;

  static void callMethod(String name, [List<Object?> arguments = const []]) {}
}
