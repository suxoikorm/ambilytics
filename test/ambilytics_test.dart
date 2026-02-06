import 'package:ambilytics/ambilytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Make instance fresh in order to avoid side effects and failing tests
  tearDown(() => resetInitialized());

  test('Ambilytics with empty params doesn\'t get initialized', () async {
    // !In debug mode test fails due to frozen FB Analytics init (until you set 'Debug My Code + Packages' in VSCode)

    // // in fact this assertion doesn't hold cause there's endless wait inside when firebase starts init and test just proceeds due to no actual await
    //expect(() async => await initAnalytics(), throwsAssertionError);
    var flag = false;
    try {
      await initAnalytics();
    } catch (_) {
      flag = true;
    }
    expect(flag, true);
    expect(ambilytics, null);
    expect(firebaseAnalytics, null);
    expect(isAmbilyticsInitialized, false);
    expect(initError, isNotNull);
  });

  test('Ambilytics with GA4 MP params gets initialized', () async {
    // Seems like Flutter test SDK always sets platform to Android
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await initAnalytics(measurementId: 'someId', apiSecret: 'someSecret');
    expect(ambilytics, isNotNull);
    expect(ambilytics!.userId, null);
    expect(ambilytics!.measurementId.isEmpty, false);
    expect(ambilytics!.apiSecret.isEmpty, false);
    expect(firebaseAnalytics, null);
    expect(isAmbilyticsInitialized, true);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Ambilytics falls back to GA4 MP params when initialized', () async {
    // Seems like Flutter test SDK always sets platform to Android
    await initAnalytics(measurementId: 'someId', apiSecret: 'someSecret', fallbackToMP: true);
    expect(ambilytics, isNotNull);
    expect(firebaseAnalytics, null);
    expect(isAmbilyticsInitialized, true);
  });

  test('Ambilytics sends app_launch event with correct platform', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(isAmbilyticsInitialized, false);
    var mock = MockAmbilyticsSession();
    // Ensure mocked sendEvent returns a Future to avoid null being awaited
    when(() => mock.sendEvent(any(), any())).thenAnswer((_) async {});
    setMockAmbilytics(mock);
    // Hiding MP params to use mocked instance instead
    await initAnalytics(
        //measurementId: 'someId', apiSecret: 'someSecret',
        fallbackToMP: true);
    expect(isAmbilyticsInitialized, true);
    expect(isAmbilyticsDisabled, false);
    final captured = verify(() => mock.sendEvent(captureAny(), captureAny())).captured;
    expect(captured[0], 'app_launch');
    expect((captured[1] as Map)['platform'], 'linux');
    debugDefaultTargetPlatformOverride = null;
  });

  test('Ambilytics sends custom_event', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var mock = MockAmbilyticsSession();
    // Ensure mocked sendEvent returns a Future to avoid null being awaited
    when(() => mock.sendEvent(any(), any())).thenAnswer((_) async {});
    setMockAmbilytics(mock);
    // Hiding MP params to use mocked instance instead
    await initAnalytics(
        //measurementId: 'someId', apiSecret: 'someSecret',
        fallbackToMP: true);
    expect(isAmbilyticsInitialized, true);
    clearInteractions(mock);
    sendEvent(name: 'custom_event', parameters: {'custom_param': 'val1'});
    final captured = verify(() => mock.sendEvent(captureAny(), captureAny())).captured;
    expect(captured[0], 'custom_event');
    expect((captured[1] as Map)['custom_param'], 'val1');
    debugDefaultTargetPlatformOverride = null;
  });

  test('Ambilytics can be disabled and sendsEvent() doesn\'t throw', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var mock = MockAmbilyticsSession();
    // Ensure mocked sendEvent returns a Future to avoid null being awaited
    when(() => mock.sendEvent(any(), any())).thenAnswer((_) async {});
    setMockAmbilytics(mock);
    // Hiding MP params to use mocked instance instead
    await initAnalytics(disableAnalytics: true);
    expect(isAmbilyticsInitialized, true);
    expect(isAmbilyticsDisabled, true);
    clearInteractions(mock);
    sendEvent(name: 'custom_event', parameters: {'custom_param': 'val1'});
    final captured = verifyNever(() => mock.sendEvent(captureAny(), captureAny())).captured;
    expect(captured.length, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  test('AmbilyticsSession has correct user ID', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    const testMeasurementId = 'testMeasurementId';
    const testApiSecret = 'testApiSecret';
    const testUserId = 'testUserId';

    await initAnalytics(
        measurementId: testMeasurementId, apiSecret: testApiSecret, userId: testUserId);

    expect(ambilytics!.userId, testUserId);

    debugDefaultTargetPlatformOverride = null;
  });

  test('Ambilytics can be disabled and re-enabled', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var mock = MockAmbilyticsSession();
    // Ensure mocked sendEvent returns a Future to avoid null being awaited
    when(() => mock.sendEvent(any(), any())).thenAnswer((_) async {});
    setMockAmbilytics(mock);
    // Hiding MP params to use mocked instance instead
    await initAnalytics();
    expect(isAmbilyticsDisabled, false);

    isAmbilyticsDisabled = true;
    clearInteractions(mock);

    sendEvent(name: 'custom_event', parameters: {'custom_param': 'val1'});
    var captured = verifyNever(() => mock.sendEvent(captureAny(), captureAny())).captured;
    expect(captured.length, 0);

    isAmbilyticsDisabled = false;
    clearInteractions(mock);

    sendEvent(name: 'custom_event', parameters: {'custom_param': 'val1'});
    captured = verify(() => mock.sendEvent(captureAny(), captureAny())).captured;
    expect(captured[0], 'custom_event');
    expect((captured[1] as Map)['custom_param'], 'val1');

    debugDefaultTargetPlatformOverride = null;
  });

  test('Firebase analytics sends app_launch event with correct platform', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var mock = MockFirebaseAnalytics();
    when(() => mock.logEvent(
        name: any(named: 'name'),
        parameters: any(named: 'parameters'),
        callOptions: any(named: 'callOptions'))).thenAnswer((_) async {});
    setMockFirebase(mock);
    await initAnalytics(fallbackToMP: true);
    expect(isAmbilyticsInitialized, true);
    final captured = verify(() => mock.logEvent(
        name: captureAny(named: 'name'),
        parameters: captureAny(named: 'parameters'),
        callOptions: captureAny(named: 'callOptions'))).captured;
    expect(captured[0], 'app_launch');
    expect((captured[1] as Map)['platform'], 'iOS');
    debugDefaultTargetPlatformOverride = null;
  });

  test('Firebase analytics sends custom_event', () async {
    var mock = MockFirebaseAnalytics();
    setMockFirebase(mock);
    when(() => mock.logEvent(
        name: any(named: 'name'),
        parameters: any(named: 'parameters'),
        callOptions: any(named: 'callOptions'))).thenAnswer((_) async {});
    await initAnalytics(fallbackToMP: true);
    expect(isAmbilyticsInitialized, true);
    clearInteractions(mock);
    sendEvent(name: 'custom_event', parameters: {'custom_param': 'val1'});
    final captured = verify(() => mock.logEvent(
        name: captureAny(named: 'name'),
        parameters: captureAny(named: 'parameters'),
        callOptions: captureAny(named: 'callOptions'))).captured;
    expect(captured[0], 'custom_event');
    expect((captured[1] as Map)['custom_param'], 'val1');
  });

  test('setUserId updates FirebaseAnalytics and currentUserId', () async {
    var mock = MockFirebaseAnalytics();
    // stub setUserId to return a Future
    when(() => mock.setUserId(id: any(named: 'id'))).thenAnswer((_) async {});
    setMockFirebase(mock);

    await setUserId('firebaseUser');

    expect(currentUserId, 'firebaseUser');
    verify(() => mock.setUserId(id: 'firebaseUser')).called(1);
  });

  test('setUserId updates AmbilyticsSession.userId and currentUserId', () async {
    // Use a real AmbilyticsSession to observe the userId field change
    final session = AmbilyticsSession(measurementId: 'm', apiSecret: 's', clientId: 'client-1');
    setMockAmbilytics(session);

    await setUserId('mpUser');

    expect(currentUserId, 'mpUser');
    expect(ambilytics!.userId, 'mpUser');
  });

  test('setUserId updates both FirebaseAnalytics and AmbilyticsSession', () async {
    var mock = MockFirebaseAnalytics();
    when(() => mock.setUserId(id: any(named: 'id'))).thenAnswer((_) async {});
    setMockFirebase(mock);

    final session = AmbilyticsSession(measurementId: 'm2', apiSecret: 's2', clientId: 'client-2');
    setMockAmbilytics(session);

    await setUserId('bothUser');

    expect(currentUserId, 'bothUser');
    verify(() => mock.setUserId(id: 'bothUser')).called(1);
    expect(ambilytics!.userId, 'bothUser');
  });

  test('Firebase analytics sends custom_event', () async {
    var mock = MockFirebaseAnalytics();
    setMockFirebase(mock);
    when(() => mock.logEvent(
        name: any(named: 'name'),
        parameters: any(named: 'parameters'),
        callOptions: any(named: 'callOptions'))).thenAnswer((_) async {});
    await initAnalytics(fallbackToMP: true);
    expect(isAmbilyticsInitialized, true);
    clearInteractions(mock);
    sendEvent(name: 'custom_event', parameters: {'custom_param': 'val1'});
    final captured = verify(() => mock.logEvent(
        name: captureAny(named: 'name'),
        parameters: captureAny(named: 'parameters'),
        callOptions: captureAny(named: 'callOptions'))).captured;
    expect(captured[0], 'custom_event');
    expect((captured[1] as Map)['custom_param'], 'val1');
  });

  test('setUserId persists user ID for MP and clears on logout', () async {
    final session = AmbilyticsSession(
        measurementId: 'm', apiSecret: 's', clientId: 'client-1');
    setMockAmbilytics(session);

    // Login as user_A
    await setUserId('user_A');
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ambilytics_user_id'), 'user_A');
    expect(ambilytics!.userId, 'user_A');
    expect(currentUserId, 'user_A');

    // Switch to user_B
    await setUserId('user_B');
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ambilytics_user_id'), 'user_B');
    expect(ambilytics!.userId, 'user_B');
    expect(currentUserId, 'user_B');

    // Logout
    await setUserId(null);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ambilytics_user_id'), null);
    expect(ambilytics!.userId, null);
    expect(currentUserId, null);
  });

  test('initAnalytics loads persisted user ID for MP', () async {
    SharedPreferences.setMockInitialValues(
        {'ambilytics_user_id': 'persisted_user'});

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await initAnalytics(measurementId: 'someId', apiSecret: 'someSecret');

    expect(currentUserId, 'persisted_user');
    expect(ambilytics!.userId, 'persisted_user');

    debugDefaultTargetPlatformOverride = null;
  });

  test('initAnalytics explicit userId overrides persisted one', () async {
    SharedPreferences.setMockInitialValues(
        {'ambilytics_user_id': 'old_user'});

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await initAnalytics(
      measurementId: 'someId',
      apiSecret: 'someSecret',
      userId: 'new_user',
    );

    expect(currentUserId, 'new_user');
    expect(ambilytics!.userId, 'new_user');

    // Verify it's also persisted
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ambilytics_user_id'), 'new_user');

    debugDefaultTargetPlatformOverride = null;
  });

  test('initAnalytics does not load persisted userId when user logged out',
      () async {
    // Simulate: user was logged in, then called setUserId(null) which removed the key
    SharedPreferences.setMockInitialValues({});

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await initAnalytics(measurementId: 'someId', apiSecret: 'someSecret');

    expect(currentUserId, null);
    expect(ambilytics!.userId, null);

    debugDefaultTargetPlatformOverride = null;
  });
}

class MockAmbilyticsObserver extends Mock implements AmbilyticsObserver {}

class MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

class MockAmbilyticsSession extends Mock implements AmbilyticsSession {}
