const appLockIdleTimeout = Duration(seconds: 60);

bool shouldLockAfterBackground({
  required Duration elapsed,
  Duration timeout = appLockIdleTimeout,
}) => elapsed >= timeout;
