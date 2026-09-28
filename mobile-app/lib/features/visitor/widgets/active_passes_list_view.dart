import 'package:flutter/material.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../models/visitor_pass_model.dart';
import '../../../repositories/visitor_repository.dart';
import '../../../theme/ncst_theme.dart';

class ActivePassesListView extends StatefulWidget {
  final Function(VisitorPass) onSelectPass;

  const ActivePassesListView({
    super.key,
    required this.onSelectPass,
  });

  @override
  State<ActivePassesListView> createState() => _ActivePassesListViewState();
}

class _ActivePassesListViewState extends State<ActivePassesListView> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<VisitorPass>>(
      valueListenable: VisitorRepository().passesNotifier,
      builder: (context, passes, _) {
        final filtered = passes.where((p) {
          final query = _search.toLowerCase();
          return p.visitorName.toLowerCase().contains(query) ||
              p.plateNumber.toLowerCase().contains(query) ||
              p.passId.toLowerCase().contains(query);
        }).toList();

        final activeCount = passes.where((p) => p.isActive).length;
        final expiredCount = passes.where((p) => p.isExpired).length;

        return Column(
          children: [
            // KPI Summary Pill Row
            Container(
              color: NcstColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _buildStatPill('ACTIVE ON CAMPUS', '$activeCount', NcstColors.green),
                  const SizedBox(width: 8),
                  _buildStatPill('EXPIRED / OVERTIME', '$expiredCount', NcstColors.crimson),
                ],
              ),
            ),
            const Divider(height: 1),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (val) => setState(() => _search = val),
                decoration: InputDecoration(
                  hintText: 'Search by visitor name or plate...',
                  hintStyle: const TextStyle(fontSize: 13, color: NcstColors.slate400),
                  prefixIcon: const Icon(Icons.search, size: 20, color: NcstColors.slate500),
                  filled: true,
                  fillColor: NcstColors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: NcstColors.slate200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: NcstColors.slate200),
                  ),
                ),
              ),
            ),

            // List of Passes
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.badge_outlined, size: 48, color: NcstColors.slate400),
                          SizedBox(height: 10),
                          Text(
                            'No visitor passes match your search.',
                            style: TextStyle(color: NcstColors.slate600, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final pass = filtered[index];
                        return _buildPassCard(pass);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatPill(String label, String count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              count,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassCard(VisitorPass pass) {
    Color statusColor;
    Color statusBg;
    if (pass.isBlocked) {
      statusColor = NcstColors.crimson;
      statusBg = NcstColors.crimsonLight;
    } else if (pass.isUsed) {
      statusColor = NcstColors.slate600;
      statusBg = NcstColors.slate200;
    } else if (pass.isExpired) {
      statusColor = NcstColors.crimson;
      statusBg = NcstColors.crimsonLight;
    } else {
      statusColor = NcstColors.green;
      statusBg = NcstColors.greenLight;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: NcstColors.slate200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onSelectPass(pass),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PlateBadge(plateNumber: pass.plateNumber),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      pass.statusDisplay,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Text(
                pass.visitorName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: NcstColors.slate900,
                ),
              ),
              const SizedBox(height: 4),

              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: NcstColors.slate500),
                  const SizedBox(width: 4),
                  Text(
                    'Entered: ${DateTimeUtils.formatTime(pass.entryTime)}  •  Valid to: ${DateTimeUtils.formatTime(pass.expiryTime)}',
                    style: const TextStyle(fontSize: 11, color: NcstColors.slate600),
                  ),
                ],
              ),
              if (pass.notes != null && pass.notes!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  pass.notes!,
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: NcstColors.slate500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
