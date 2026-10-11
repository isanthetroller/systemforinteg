import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/ncst_theme.dart';
import '../../auth/screens/login_screen.dart';

/// The native launch artwork and this first Flutter frame share the same mark
/// and background, so the handoff does not flash between unrelated screens.
class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key});

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
    final logoSize =
        MediaQuery.sizeOf(context).shortestSide.clamp(0.0, 400.0) * 0.36;

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
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.25),
              radius: 1.1,
              colors: [Color(0xFF15316F), NcstColors.navyDark],
            ),
          ),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final logoEntrance = Curves.easeOutBack.transform(
                  (_controller.value / 0.55).clamp(0.0, 1.0),
                );
                final textEntrance = Curves.easeOutCubic.transform(
                  ((_controller.value - 0.28) / 0.5).clamp(0.0, 1.0),
                );
                final progress = Curves.easeInOutCubic.transform(
                  ((_controller.value - 0.4) / 0.6).clamp(0.0, 1.0),
                );
                return Column(
                  children: [
                    const Spacer(flex: 2),
                    Semantics(
                      label: 'NCST SecurePark is opening',
                      child: Transform.scale(
                        scale: reducedMotion ? 1 : 0.78 + 0.22 * logoEntrance,
                        child: Opacity(
                          opacity: reducedMotion
                              ? 1
                              : logoEntrance.clamp(0.0, 1.0),
                          child: Container(
                            width: logoSize + 28,
                            height: logoSize + 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: NcstColors.gold.withValues(alpha: 0.15),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: NcstColors.gold.withValues(
                                    alpha: 0.12 * progress,
                                  ),
                                  blurRadius: 36,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/securepark_mark.png',
                              width: logoSize,
                              height: logoSize,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Opacity(
                      opacity: reducedMotion ? 1 : textEntrance,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          reducedMotion ? 0 : 12 * (1 - textEntrance),
                        ),
                        child: const Column(
                          children: [
                            Text(
                              'NCST SECUREPARK',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.2,
                              ),
                            ),
                            SizedBox(height: 7),
                            Text(
                              'Gate Security Terminal',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFD4DEF2),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(flex: 2),
                    SizedBox(
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
                    const SizedBox(height: 22),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
