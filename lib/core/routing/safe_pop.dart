import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension SafePop on BuildContext {
  /// [GoRouter.pop] throws `GoError('There is nothing to pop')` when the
  /// current page is the only one in the stack — which is exactly what
  /// happens after a cold-start resume (app_router.dart redirects straight
  /// to the saved location), a web deep link, or a notification tap that
  /// opens a screen with nothing beneath it. Back buttons call this instead:
  /// pop when there's somewhere to go back to, otherwise land on [fallback].
  void popOrGo(String fallback) {
    if (canPop()) {
      pop();
    } else {
      go(fallback);
    }
  }
}
