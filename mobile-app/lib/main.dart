import 'dart:async';
import 'package:flutter/material.dart';
import 'core/constants/api_constants.dart';
import 'features/auth/screens/login_screen.dart';
import 'services/local_cache_service.dart';
import 'services/sync_queue_service.dart';
import 'theme/ncst_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local persistent caching for offline Wi-Fi resilience
  await LocalCacheService.init();

  // Initialize persistent server endpoint (defaults to live cloud, persists user selection)
  ApiConstants.baseUrl = LocalCacheService.getServerBaseUrl(defaultUrl: ApiConstants.defaultBaseUrl);

  // Start automated background synchronization queue for offline data flush
  SyncQueueService().startAutoSync();
  // Also send anything waiting the moment the app returns to the foreground (for example after the phone reconnects)
  WidgetsBinding.instance.addObserver(_SyncOnResume());

  // Cut memory footprint: Default Flutter imageCache allows 1000 images and 100 MB of uncompressed bitmaps.
  // In a mobile terminal scanning QR passes with camera textures and photos, capping to 40 images / 25 MB
  // aggressively evicts stale bitmaps and reduces RAM pressure.
  PaintingBinding.instance.imageCache.maximumSize = 40;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 25 * 1024 * 1024; // 25 MB

  runApp(const NcstGateSecurityApp());
}

/// Flushes the offline queue as soon as the app is back in front of the guard.
class _SyncOnResume with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
      home: const LoginScreen(),
    );
  }
}
