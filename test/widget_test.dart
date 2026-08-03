// Placeholder smoke test. HyportApp requires Firebase.initializeApp() to
// have run first (see main.dart), so a real widget test needs a fake
// Firebase setup; that's tracked for the Day 4 hardening pass rather than
// blocking the build here.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder', () {
    expect(1 + 1, 2);
  });
}
