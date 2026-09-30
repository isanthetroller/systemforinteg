import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Start / stop calls for the QR scanner camera that can never leave an unhandled exception behind.
///
/// `MobileScannerController.start()` and `stop()` return Futures. Wrapping the bare call in `try { ... } catch (_) {}`
/// only catches errors thrown immediately, so a failure that arrives later (for example "the controller is still
/// initializing" when the app is resumed while the camera is starting, or "already started") escaped as an unhandled
/// async exception. These wrappers await the call inside the try block.
///
/// Losing a start/stop race is harmless here (the camera is either already in the wanted state or the user is not
/// scanning), so the error is logged in debug builds and otherwise ignored.
extension SafeScannerControl on MobileScannerController {
  Future<void> startSafely() async {
    try {
      await start();
    } catch (e) {
      debugPrint('[Scanner] start ignored: $e');
    }
  }

  Future<void> stopSafely() async {
    try {
      await stop();
    } catch (e) {
      debugPrint('[Scanner] stop ignored: $e');
    }
  }
}
