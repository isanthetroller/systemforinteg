import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/ncst_theme.dart';
import '../../auth/screens/login_screen.dart';

/// The native launch artwork (Android 12 splash icon / launch bitmap) and this first Flutter frame show the
/// same NCST badge at the same size and the same screen position, so the hand-off does not flash or jump.
/// The badge is therefore visible from the first frame; only the text and the progress bar animate in.
class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key});

  /// Diameter of the badge in logical pixels. Keep in step with DISC_DP in tool/generate_ncst_launch_assets.py.
  static const double badgeSize = 160;

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  )..addStatusListener(_onAnimationStatus);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final entrance = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: entrance,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.035),
                end: Offset.zero,
              ).animate(entrance),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: NcstColors.navyDark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: NcstColors.navyDark,
        // The Scaffold gives its body loose constraints: without an explicit full-size box the gradient (and the
        // content) shrinks to the widest child and sits in the top-left corner.
        body: SizedBox.expand(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.1),
                radius: 1.1,
                colors: [Color(0xFF15316F), NcstColors.navyDark],
              ),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final textEntrance = Curves.easeOutCubic.transform(
                  ((_controller.value - 0.15) / 0.5).clamp(0.0, 1.0),
                );
                final progress = Curves.easeInOutCubic.transform(
                  ((_controller.value - 0.2) / 0.8).clamp(0.0, 1.0),
                );
                return LayoutBuilder(
                  builder: (context, box) {
                    // Badge centre = screen centre, exactly where the native splash draws it
                    final textTop =
                        box.maxHeight / 2 + LaunchScreen.badgeSize / 2 + 28;
                    return Stack(
                      children: [
                        Center(
                          child: Semantics(
                            label: 'NCST SecurePark is opening',
                            child: Container(
                              width: LaunchScreen.badgeSize,
                              height: LaunchScreen.badgeSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: NcstColors.gold.withValues(
                                      alpha: 0.20 * progress,
                                    ),
                                    blurRadius: 40,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/ncst_mark.png',
                                width: LaunchScreen.badgeSize,
                                height: LaunchScreen.badgeSize,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: textTop,
                          left: 24,
                          right: 24,
                          child: Opacity(
                            opacity: reducedMotion ? 1 : textEntrance,
                            child: Transform.translate(
                              offset: Offset(
                                0,
                                reducedMotion ? 0 : 12 * (1 - textEntrance),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // scaleDown: never clipped on narrow screens or with a large system font
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: const Text(
                                      'NCST SECUREPARK',
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 23,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: const Text(
                                      'Gate Security Terminal',
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFFD4DEF2),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: bottomInset + 36,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: SizedBox(
                              width: 84,
                              height: 3,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: reducedMotion ? 1 : progress,
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: NcstColors.gold,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
