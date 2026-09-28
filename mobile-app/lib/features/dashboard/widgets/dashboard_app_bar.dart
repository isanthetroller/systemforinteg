import 'package:flutter/material.dart';
import '../../../theme/ncst_theme.dart';

class DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DashboardAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isVeryNarrow = screenWidth < 380;

    return AppBar(
      titleSpacing: isVeryNarrow ? 8 : NavigationToolbar.kMiddleSpacing,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: NcstColors.gold,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'NCST',
              style: TextStyle(
                color: NcstColors.navyDark,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'Gate Security Terminal',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: EdgeInsets.symmetric(horizontal: isVeryNarrow ? 6 : 8, vertical: 4),
          decoration: BoxDecoration(
            color: NcstColors.navyDark,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.login, size: 14, color: NcstColors.gold),
              const SizedBox(width: 4),
              Text(
                isVeryNarrow ? 'ENTRY' : 'ENTRY GATE',
                style: const TextStyle(
                  color: NcstColors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
