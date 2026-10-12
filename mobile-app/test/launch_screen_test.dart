import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/features/splash/screens/launch_screen.dart';

/// Regression: the launch content used to be a Column inside a loose Scaffold body, so the gradient box shrank to the
/// width of the title and the whole screen sat in the top-left corner (title clipped). The badge also started invisible
/// and at a different size/position than the native splash, which made the hand-off flicker.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, {double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
          child: const LaunchScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final size in const [Size(360, 800), Size(412, 915), Size(320, 568)]) {
    testWidgets('launch content fills the screen and the badge is centred at $size', (tester) async {
      await pumpAt(tester, size);

      final gradient = find.byWidgetPredicate(
        (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient != null,
      );
      expect(tester.getSize(gradient), size, reason: 'gradient box must cover the whole screen, not the title width');

      final badge = find.byWidgetPredicate((w) => w is Image && w.width == LaunchScreen.badgeSize);
      final centre = tester.getCenter(badge);
      expect(centre.dx, closeTo(size.width / 2, 0.5));
      expect(centre.dy, closeTo(size.height / 2, 0.5), reason: 'same screen position as the native splash');
      expect(tester.getSize(badge), const Size(LaunchScreen.badgeSize, LaunchScreen.badgeSize));

      final badgeOpacity = find.ancestor(of: badge, matching: find.byType(Opacity));
      expect(badgeOpacity, findsNothing, reason: 'badge is visible from the first frame (no fade-in flicker)');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('title stays inside the screen with a very large system font', (tester) async {
    const size = Size(320, 568);
    await pumpAt(tester, size, textScale: 2.0);
    await tester.pump(const Duration(milliseconds: 900));
    final title = find.text('NCST SECUREPARK');
    final rect = tester.getRect(title);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(size.width));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
