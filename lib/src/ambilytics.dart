import 'dart:convert';

import 'package:ambilytics/src/device_platform.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

AmbilyticsSession? _ambilytics;
FirebaseAnalytics? _firebaseAnalytics;
Object? _initError;

// Analytics can be initialize but disabled in case disabling occurs after initialization
bool _initialized = false;
bool _disabled = true;

// Store user ID separately for external management
String? _currentUserId;

const _clientIdField = 'ambilytics_client_id';
const _userIdField = 'ambilytics_user_id';

/// GA4 Measurement Protocol backend
AmbilyticsSession? get ambilytics => _ambilytics;

/// Firebase Analytics backend
FirebaseAnalytics? get firebaseAnalytics => _firebaseAnalytics;

/// Whether analytics initialization was successfully completed
bool get isAmbilyticsInitialized => _initialized;

/// If error occurred during initialization error is not thrown yet detail is saved in this property
Object? get initError => _initError;

/// Stop or resume sending events
bool get isAmbilyticsDisabled => _disabled;
set isAmbilyticsDisabled(value) => _disabled = value;

/// Get current user ID
String? get currentUserId => _currentUserId;

@visibleForTesting
void setMockAmbilytics(AmbilyticsSession ambilyticsSession) {
  _ambilytics = ambilyticsSession;
}

@visibleForTesting
void setMockFirebase(FirebaseAnalytics fa) {
  _firebaseAnalytics = fa;
}

@visibleForTesting
void resetInitialized() {
  _initialized = false;
  _ambilytics = null;
  _firebaseAnalytics = null;
  _currentUserId = null;
}

/// Sets or updates the user ID for analytics
/// This will update both Firebase Analytics and Measurement Protocol if they are initialized
Future<void> setUserId(String? userId) async {
  _currentUserId = userId;

  if (_firebaseAnalytics != null) {
    await _firebaseAnalytics!.setUserId(id: userId);
  }

  if (_ambilytics != null) {
    _ambilytics!.userId = userId;
    // Persist user ID for MP (Firebase handles its own persistence)
    final prefs = await SharedPreferences.getInstance();
    if (userId != null) {
      await prefs.setString(_userIdField, userId);
    } else {
      await prefs.remove(_userIdField);
    }
  }
}

Future<String?> getFirebaseAppInstanceId() async {
  if (_firebaseAnalytics != null) {
    return await _firebaseAnalytics!.appInstanceId;
  }
  return null;
}

// TODO: consider adding a flag to send platform as param with all events (that would be needed to show platform as dimension)
// Challenge is tha it can be done for all custom events, not sure about standard (e.g. screen_view)

/// Prepares analytics for usage. Doesn't throw errors, in debug mode throws assertions. If Ambilytics fails to initialize [isAmbilyticsInitialized] returns false.
///
/// If the platform is Android, iOS, macOS, or Web, Firebase Analytics will be used ([_firebaseAnalytics] instance will be initialized).
/// Otherwise, GA4 Measurement protocol and custom events will be used ([_ambilytics] instance will be initialized).
///
/// If [fallbackToMP] is true, than Measurement Protocol will be used if Firebase analytics fails to initialize. E.g. you can skip configuring Firebase Analytics in native projects and use MP for all platforms.
///
/// If [disableAnalytics] is `true`, analytics will not be initialized, any analytics calls will be ignored,
/// [_firebaseAnalytics] and [_ambilytics] instances will be null. Useful for the scenarios when toy wish to disable analytics.
///
/// If [sendAppLaunch] is true, "app_launch" will be sent with "platform" param value corresponding runtime platform (i.e. Windows)
///
/// [apiSecret] and [measurementId] must be set in order to enable GA4 Measurement protocol and have [_ambilytics] initialized.
///
/// [userId] allows setting initial user identifier. Can be updated later using [setUserId].
Future<void> initAnalytics({
  bool disableAnalytics = false,
  bool fallbackToMP = false,
  bool sendAppLaunch = true,
  String? measurementId,
  String? apiSecret,
  String? userId,
}) async {
  _disabled = disableAnalytics;
  if (_initialized) return;

  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Store the provided user ID
    _currentUserId = userId;

    // Initialize Firebase Analytics for supported platforms
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        kIsWeb) {
      try {
        _firebaseAnalytics = FirebaseAnalytics.instance;

        if (_currentUserId != null) {
          await _firebaseAnalytics!.setUserId(id: _currentUserId);
        }

        _initialized = true;

        if (sendAppLaunch && !_disabled) {
          _sendAppLaunchEvent();
        }

        return;
      } catch (e) {
        if (fallbackToMP) {
          print(
              'Error initializing Firebase Analytics, falling back to Measurement Protocol. \n$e');
        } else {
          rethrow;
        }
      }
    }

    // Use measurement protocol
    bool isNewInstallation = false;
    if (measurementId != null && apiSecret != null) {
      // Get or create client ID (unique per installation)
      SharedPreferences prefs = await SharedPreferences.getInstance();

      String? clientId = prefs.getString(_clientIdField);
      if (clientId == null) {
        isNewInstallation = true;
        clientId = const Uuid().v4();
        await prefs.setString(_clientIdField, clientId);
      }

      // Load persisted user ID or use explicitly provided one
      if (userId != null) {
        await prefs.setString(_userIdField, userId);
      } else {
        final persistedUserId = prefs.getString(_userIdField);
        if (persistedUserId != null) {
          _currentUserId = persistedUserId;
        }
      }

      _ambilytics = AmbilyticsSession(
        measurementId: measurementId,
        apiSecret: apiSecret,
        clientId: clientId,
        userId: _currentUserId,
        useValidationServer: false,
      );
    }

    if (_ambilytics != null || _firebaseAnalytics != null) {
      _initialized = true;
      // Send first_open for new MP installations so GA4 registers the user
      if (isNewInstallation && _ambilytics != null && !_disabled) {
        await _ambilytics!.sendEvent('first_open', null);
      }
      if (sendAppLaunch && !_disabled) {
        _sendAppLaunchEvent();
      }
    } else {
      _initError = 'Neither Firebase Analytics nor Measurement Protocol have been initialized';
      assert(false, _initError);
    }
  } catch (e) {
    _initialized = false;
    _initError = e;
    assert(false, 'Can\'t init analytics due to error.\n\n$e');
  }
}

void _sendAppLaunchEvent() {
  final params = {
    'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    'device_platform': DevicePlatform.current,
  };
  sendEvent(name: PredefinedEvents.appLaunch, parameters: params);
}

/// Sends a given [eventName] with given [params] using either [firebaseAnalytics]
/// or Measurement Protocol [ambilytics]. It tries Firebase Analytics first (if it is initialized)
/// then it goes to MP. It doesn't send events with both protocols, just one
Future<void> sendEvent({required String name, Map<String, Object>? parameters}) async {
  if (!_initialized) return;
  if (_disabled) return;

  assert(!reservedGa4Events.contains(name),
      'Event name "$name" is reserved by GA4 and cannot be used');
  assert(name.isNotEmpty && name.length <= 40,
      'Event name should be between 1 and 40 characters long');

  if (_firebaseAnalytics != null) {
    await _firebaseAnalytics!.logEvent(name: name, parameters: parameters);
  } else if (_ambilytics != null) {
    await _ambilytics!.sendEvent(name, parameters);
  }
}

/// Filter out non PageRoute ones
bool defaultRouteFilter(Route<dynamic>? route) => route is PageRoute;

/// Accepts any routes, e.g. the ones added via showDialog()
bool anyRouteFilter(Route<dynamic>? route) => true;
String? defaultNameExtractor(RouteSettings settings) => settings.name;

/// Alternative to [FirebaseAnalyticsObserver] which intercepts
/// Flutter navigation events and send screen view events.
/// The difference is that for unsupported platforms (e.g. Linux, Window)
/// of if FirebaseAnalytics is not configured
/// the app uses Measurement Protocol and sends custom 'screen_view_cust'
/// event together with screen name.
class AmbilyticsObserver extends RouteObserver<ModalRoute<dynamic>> {
  AmbilyticsObserver({
    this.nameExtractor = defaultNameExtractor,
    this.routeFilter = defaultRouteFilter,
    this.alwaySendScreenViewCust = false,
    Function(PlatformException error)? onError,
  }) : assert(_initialized, 'Ambilytics must be initialized first') {
    if (_firebaseAnalytics != null) {
      faObserver = FirebaseAnalyticsObserver(
        analytics: _firebaseAnalytics!,
        nameExtractor: nameExtractor,
        routeFilter: routeFilter,
        onError: onError,
      );
    }
  }

  FirebaseAnalyticsObserver? faObserver;
  final ScreenNameExtractor nameExtractor;
  final RouteFilter routeFilter;
  final bool alwaySendScreenViewCust;
  void Function(PlatformException error)? onError;

  Future<void> _sendScreenView(Route<dynamic> route) async {
    final screenName = nameExtractor(route.settings);
    if (screenName == null) {
      debugPrint('Warning: Route has no name, skipping screen view event');
      return;
    }

    if (_ambilytics != null) {
      await _ambilytics!.sendEvent(PredefinedEvents.screenViewCust, {'screen_name': screenName});
    } else {
      await _firebaseAnalytics!
          .logEvent(name: PredefinedEvents.screenViewCust, parameters: {'screen_name': screenName});
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_initialized) return;
    if (_disabled) return;

    super.didPush(route, previousRoute);
    if (faObserver != null) {
      faObserver!.didPush(route, previousRoute);
      if (!alwaySendScreenViewCust) return;
    }
    if (routeFilter(route)) {
      _sendScreenView(route);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (!_initialized) return;
    if (_disabled) return;

    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (faObserver != null) {
      faObserver!.didReplace(newRoute: newRoute, oldRoute: oldRoute);
      if (!alwaySendScreenViewCust) return;
    }
    if (newRoute != null && routeFilter(newRoute)) {
      _sendScreenView(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_initialized) return;
    if (_disabled) return;

    super.didPop(route, previousRoute);
    if (faObserver != null) {
      faObserver!.didPop(route, previousRoute);
      if (!alwaySendScreenViewCust) return;
    }
    if (previousRoute != null && routeFilter(previousRoute) && routeFilter(route)) {
      _sendScreenView(previousRoute);
    }
  }
}

class AmbilyticsSession {
  AmbilyticsSession({
    required this.measurementId,
    required this.apiSecret,
    required this.clientId,
    this.userId,
    this.useValidationServer = false,
  }) {
    _sessionId = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
  }

  final String measurementId;
  final String apiSecret;
  final String clientId; // Unique per installation
  String? userId; // Can be null and updated later

  final DateTime sessionStarted = DateTime.now().toUtc();
  String get sessionId => _sessionId;
  late final String _sessionId;

  // https://developers.google.com/analytics/devguides/collection/protocol/ga4/validating-events?client_type=gtag
  final bool useValidationServer;

  /// Sends an event to the analytics service.
  /// [eventName] is the name of the event. Max length is 40 characters.
  /// [params] is a Map of additional parameters to attach to the event.
  Future<void> sendEvent(String eventName, Map<String, Object?>? params) async {
    assert(eventName.length <= 40, 'Event name exceeds 40 characters limit');
    assert(eventName.isNotEmpty && RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(eventName),
        'Event name should start with a letter and contain only letters, numbers, and underscores.');

    Map<String, Object?> defParams = {
      'engagement_time_msec': DateTime.now().toUtc().difference(sessionStarted).inMilliseconds,
      'session_id': sessionId,
    };

    if (params != null) {
      defParams.addAll(params);
    }

    final Map<String, dynamic> bodyMap = {
      'client_id': clientId, // Use unique client ID instead of platform name
      'events': [
        {'name': eventName, 'params': defParams}
      ]
    };

    // Add user_id only if it's set
    if (userId != null) {
      bodyMap['user_id'] = userId;
    }

    var body = jsonEncode(bodyMap);

    var headers = {
      'Content-Type': 'application/json',
    };

    headers['Accept-Language'] = PlatformDispatcher.instance.locale.toLanguageTag();

    try {
      final response = await http.post(
        Uri.parse(
            'https://www.google-analytics.com/${useValidationServer ? 'debug/' : ''}mp/collect?measurement_id=$measurementId&api_secret=$apiSecret'),
        headers: headers,
        body: body,
      );

      if (useValidationServer && response.statusCode == 200) {
        // Log validation response for debugging
        debugPrint('GA4 Validation Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error sending event to GA4: $e');
    }
  }
}

abstract class PredefinedEvents {
  static const appLaunch = "app_launch";
  static const screenViewCust = "screen_view_cust";
}

/// [GA4] Automatically collected events, they are forbidden for use
/// https://support.google.com/analytics/answer/9234069
const Set<String> reservedGa4Events = {
  'ad_activeview',
  'ad_click',
  'ad_exposure',
  'ad_impression',
  'ad_query',
  'ad_reward',
  'adunit_exposure',
  'app_background',
  'app_clear_data',
  'app_exception',
  'app_remove',
  'app_store_refund',
  'app_store_subscription_cancel',
  'app_store_subscription_convert',
  'app_store_subscription_renew',
  'app_uninstall',
  'app_update',
  'app_upgrade',
  'click',
  'dynamic_link_app_open',
  'dynamic_link_app_update',
  'dynamic_link_first_open',
  'error',
  'file_download',
  'firebase_campaign',
  'firebase_in_app_message_action',
  'firebase_in_app_message_dismiss',
  'firebase_in_app_message_impression',
  'first_open',
  'first_visit',
  'form_start',
  'form_submit',
  'in_app_purchase',
  'notification_dismiss',
  'notification_foreground',
  'notification_open',
  'notification_receive',
  'os_update',
  'page_view',
  'screen_view',
  'scroll',
  'session_start',
  'session_start_with_rollout',
  'user_engagement',
  'video_complete',
  'video_progress',
  'video_start',
  'view_search_results'
};
