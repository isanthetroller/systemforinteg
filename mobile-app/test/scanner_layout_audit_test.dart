// Temporary layout measurement. Simulated camera texture, actual viewfinder layout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/features/scanner/widgets/camera_viewfinder.dart';

void main() {
  testWidgets('measure scan-box placement in the embedded guard layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [
      const Size(390, 844),
      const Size(360, 800),
      const Size(844, 390),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Guard terminal')),
            bottomNavigationBar: const SizedBox(height: 72),
            body: Column(
              children: [
                AppBar(title: const Text('Scan Driver QR Pass')),
                Expanded(
                  child: CameraViewfinder(
                    cameraController: null,
                    cameraHasError: false,
                    onQrDetected: (_) {},
                    onManualQrPressed: () {},
                    onFlipCameraPressed: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final area = tester.getRect(find.byType(CameraViewfinder));
      final frame = tester.getRect(find.byType(AnimatedContainer));
      final delta = frame.center - area.center;
      debugPrint(
        'LAYOUT ${size.width}x${size.height} area=$area frame=$frame deltaX=${delta.dx} deltaY=${delta.dy}',
      );
      expect(delta.dx.abs(), lessThan(1));
      expect(tester.takeException(), isNull);
    }
  });
}
