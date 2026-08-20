// Platform-conditional browser-back-button guard.
//
// On Flutter Web, PopScope only intercepts the AppBar back button and the
// Android/iOS system back gesture — it does NOT reliably intercept the
// browser's own native Back button, because that fires a `popstate` event
// after the browser has already moved to the previous history entry, with
// no way to cancel it. The standard workaround (used here) is to push an
// extra history entry when a screen needs to guard against back navigation;
// a `popstate` then just means "the guard entry was consumed" — we
// immediately re-push it (invisible to the user, same URL) and run our own
// callback (e.g. show a confirmation dialog, or redirect) instead of letting
// the framework silently re-render a stale screen state.
//
// On mobile/other platforms this is a no-op: PopScope's own interception
// already covers the system back gesture correctly there.
export 'browser_back_guard_stub.dart'
    if (dart.library.html) 'browser_back_guard_web.dart';
