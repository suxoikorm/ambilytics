## 2.0.0
- Added user ID management: `setUserId(String?)` and `currentUserId`.
- AmbilyticsSession: support mutable `userId` and `clientId` (persisted as `ambilytics_client_id`).
- initAnalytics accepts an initial `userId` and applies it to Firebase when available.
- Persist client id in SharedPreferences for Measurement Protocol sessions.
- Internal fixes: event validation, screen view handling, and error assertions.
- Tests updated to cover user id behavior and mocked async methods.

## 1.1.0

- Readme updates
- Spelling fixes
- Public API update (AmbilyticsSession.measurementId spelling fixed)

## 1.0.7

- Bumped up firebase_analytics versions to ^11.3.1

## 1.0.5

- Measurement Protocol, fixed user id (issue #2)
- Bumped dependency versions
- Cleaned up /example

## 1.0.4

- Bumped dependency versions

## 1.0.3

- Readme updates

## 1.0.2

- Correct platforms sent with app_launch in Web
- Fixed example on iOS

## 1.0.1

- Readme fixed
- Supported platforms updated

## 1.0.0

- Initial version.
