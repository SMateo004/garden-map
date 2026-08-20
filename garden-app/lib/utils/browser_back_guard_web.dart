import 'dart:html' as html;

html.EventListener? _popStateListener;

void armBrowserBackGuard(void Function() onBack) {
  disarmBrowserBackGuard();
  html.window.history.pushState(null, '', html.window.location.href);
  _popStateListener = (event) {
    // Re-absorb the guard entry we just consumed, then hand control to the
    // caller instead of letting the browser's default pop stand.
    html.window.history.pushState(null, '', html.window.location.href);
    onBack();
  };
  html.window.addEventListener('popstate', _popStateListener);
}

void disarmBrowserBackGuard() {
  if (_popStateListener != null) {
    html.window.removeEventListener('popstate', _popStateListener);
    _popStateListener = null;
  }
}
