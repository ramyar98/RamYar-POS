// The app is landscape-only: the floor plan, the bill and the tables are laid
// out for a wide screen. These checks pin the lock in the three places that
// actually control it, so a future edit cannot quietly let the device turn back
// to portrait. They are static (they read the shipped files) because the real
// behaviour is enforced by Android/iOS before Flutter even draws a frame.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Android manifest locks the activity to landscape', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:screenOrientation="sensorLandscape"'),
        reason: 'the activity must be sensorLandscape so it never rotates to '
            'portrait, even before Flutter starts');
    expect(manifest, isNot(contains('android:screenOrientation="portrait"')),
        reason: 'a portrait lock would directly contradict the requirement');
  });

  test('main() pins the runtime orientation to landscape as well', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('SystemChrome.setPreferredOrientations'),
        reason: 'the runtime lock must be set before the first frame');
    expect(main, contains('DeviceOrientation.landscapeLeft'));
    expect(main, contains('DeviceOrientation.landscapeRight'));
    expect(main, isNot(contains('DeviceOrientation.portraitUp')));
    expect(main, isNot(contains('DeviceOrientation.portraitDown')));
  });

  test('the iOS plist offers only landscape', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('UIInterfaceOrientationLandscapeLeft'));
    expect(plist, contains('UIInterfaceOrientationLandscapeRight'));
    expect(plist, isNot(contains('UIInterfaceOrientationPortrait')),
        reason: 'portrait (and portrait upside-down) must not be offered');
  });
}
