import 'package:flutter/material.dart';
import 'features/auth/screens/login_screen.dart';
import 'services/local_cache_service.dart';
import 'services/sync_queue_service.dart';
import 'theme/ncst_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local persistent caching for offline Wi-Fi resilience
  await LocalCacheService.init();

  // Start automated background synchronization queue for offline data flush
  SyncQueueService().startAutoSync();

  // Cut memory footprint: Default Flutter imageCache allows 1000 images and 100 MB of uncompressed bitmaps.
  // In a mobile terminal scanning QR passes with camera textures and photos, capping to 40 images / 25 MB
  // aggressively evicts stale bitmaps and reduces RAM pressure.
  PaintingBinding.instance.imageCache.maximumSize = 40;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 25 * 1024 * 1024; // 25 MB

  runApp(const NcstGateSecurityApp());
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
