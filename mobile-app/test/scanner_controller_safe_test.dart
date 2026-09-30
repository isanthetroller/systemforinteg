import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:systemforinteg/core/utils/scanner_controller_safe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SafeScannerControl (resume / pause of the QR camera)', () {
    test('a raw start() fails asynchronously here, which is exactly what the old try/catch could not catch', () async {
      final controller = MobileScannerController(autoStart: false);
      addTearDown(() async {
        try {
          await controller.dispose();
        } catch (_) {}
      });

      // No camera plugin in a unit test: the failure arrives from the awaited Future, not from the call itself.
      var threw = false;
      try {
        final pending = controller.start(); // returning the Future does not throw...
        await pending; // ...the failure only shows up when it is awaited
      } catch (_) {
        threw = true;
      }
      expect(threw, isTrue);
    });

    test('startSafely / stopSafely complete normally even when the camera call fails', () async {
      final controller = MobileScannerController(autoStart: false);
      addTearDown(() async {
        try {
          await controller.dispose();
        } catch (_) {}
      });

      await controller.startSafely();
      await controller.stopSafely();
    });

    test('they are also safe to call through a null-aware access when there is no controller', () async {
      const MobileScannerController? none = null;
      await none?.startSafely();
      await none?.stopSafely();
    });
  });
}
