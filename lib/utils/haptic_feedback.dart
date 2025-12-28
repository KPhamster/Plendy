import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _heavyTapResetDelay = Duration(milliseconds: 80);
bool _heavyTapInProgress = false;
const _heavyTapSentinel = Object();

void triggerHeavyHaptic() {
  if (kIsWeb) return;
  if (_heavyTapInProgress) return;
  _heavyTapInProgress = true;
  HapticFeedback.heavyImpact();
  Timer(_heavyTapResetDelay, () {
    _heavyTapInProgress = false;
  });
}

// Wrap callbacks to add heavy haptics while preserving their signature.
T? withHeavyTap<T extends Function>(T? callback) {
  if (callback == null) return null;
  return (([
    dynamic a = _heavyTapSentinel,
    dynamic b = _heavyTapSentinel,
    dynamic c = _heavyTapSentinel,
  ]) {
    triggerHeavyHaptic();
    final args = <dynamic>[];
    if (!identical(a, _heavyTapSentinel)) args.add(a);
    if (!identical(b, _heavyTapSentinel)) args.add(b);
    if (!identical(c, _heavyTapSentinel)) args.add(c);
    Function.apply(callback, args);
  }) as T;
}
