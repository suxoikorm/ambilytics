import 'dart:io';

import 'package:flutter/foundation.dart';

class DevicePlatform {
  static bool? _testIsWindows = false;

  @visibleForTesting
  static set testIsWindows(bool? value) => _testIsWindows = value;

  /// Current platform is Web
  static bool get isWeb => kIsWeb;

  /// Current platform is Android or iOS
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Current platform is Android
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Current platform is iOS
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// Current platform is macOS, Windows or Linux
  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Current platform is macOS
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// Current platform is Windows
  static bool get isWindows => !kIsWeb && (_testIsWindows == true || Platform.isWindows);

  /// Return current platform as string
  static String get current {
    if (isWeb) {
      return 'web';
    } else if (isAndroid) {
      return 'android';
    } else if (isIOS) {
      return 'ios';
    } else if (isMacOS) {
      return 'macos';
    } else if (isWindows) {
      return 'windows';
    } else {
      return 'unknown';
    }
  }
}
