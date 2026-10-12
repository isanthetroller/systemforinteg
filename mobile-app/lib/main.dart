import 'dart:async';

import 'package:flutter/material.dart';

import 'core/constants/api_constants.dart';
import 'features/splash/screens/launch_screen.dart';
import 'services/local_cache_service.dart';
import 'services/sync_queue_service.dart';
import 'theme/ncst_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local persistent caching for offline Wi-Fi resilience
  await LocalCacheService.init();

  // Initialize persistent server endpoint (defaults to live cloud, persists user selection)
  ApiConstants.baseUrl = LocalCacheService.getServerBaseUrl(
    defaultUrl: ApiConstants.defaultBaseUrl,
  );

  // Start automated background synchronization queue for offline data flush
  SyncQueueService().startAutoSync();
  // Also send anything waiting the moment the app returns to the foreground (for example after the phone reconnects)
  WidgetsBinding.instance.addObserver(_SyncOnResume());

  // Cut memory footprint: Default Flutter imageCache allows 1000 images and 100 MB of uncompressed bitmaps.
  // In a mobile terminal scanning QR passes with camera textures and photos, capping to 40 images / 25 MB
  // aggressively evicts stale bitmaps and reduces RAM pressure.
  PaintingBinding.instance.imageCache.maximumSize = 40;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      25 * 1024 * 1024; // 25 MB

  // Decode the launch badge before the first frame: the system splash hands over to it, and a badge that is still
  // decoding on that frame shows as a blank navy flash.
  await _preload(const AssetImage('assets/images/ncst_mark.png'));

  runApp(const NcstGateSecurityApp());
}

/// Resolves [provider] into Flutter's image cache without needing a BuildContext. Never throws or waits forever.
Future<void> _preload(ImageProvider provider) {
  final done = Completer<void>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish() {
    stream.removeListener(listener);
    if (!done.isCompleted) done.complete();
  }

  listener = ImageStreamListener((_, _) => finish(), onError: (_, _) => finish());
  stream.addListener(listener);
  return done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
}

/// Flushes the offline queue as soon as the app is back in front of the guard.
class _SyncOnResume with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) SyncQueueService().stopAutoSync();
    if (state == AppLifecycleState.resumed) {
      SyncQueueService().startAutoSync();
      SyncQueueService().requestRefresh();
      unawaited(SyncQueueService().processQueue());
    }
  }
}

class NcstGateSecurityApp extends StatelessWidget {
  const NcstGateSecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NCST Gate Security Terminal',
      debugShowCheckedModeBanner: false,
      theme: NcstTheme.lightTheme,
      home: const LaunchScreen(),
    );
  }
}
