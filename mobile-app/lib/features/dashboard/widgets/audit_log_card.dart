import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/vehicle_model.dart';
import '../../../theme/ncst_theme.dart';
import 'audit_log_item_row.dart';

class AuditLogCard extends StatelessWidget {
  final List<AuditLogEntry> logs;
  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const AuditLogCard({
    super.key,
    required this.logs,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with filters (Responsive)
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 450;
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.history, color: NcstColors.navy, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'AUDIT LOG',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: NcstColors.slate800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: AppConstants.auditLogFilters.map((filter) {
                            final isSelected = selectedFilter == filter;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  filter,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? NcstColors.white : NcstColors.slate600,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: NcstColors.navy,
                                backgroundColor: NcstColors.slate100,
                                showCheckmark: false,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                onSelected: (val) {
                                  if (val) onFilterChanged(filter);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    const Icon(Icons.history, color: NcstColors.navy, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'AUDIT LOG',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: NcstColors.slate800,
                      ),
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 6,
                      children: AppConstants.auditLogFilters.map((filter) {
                        final isSelected = selectedFilter == filter;
                        return ChoiceChip(
                          label: Text(
                            filter,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? NcstColors.white : NcstColors.slate600,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: NcstColors.navy,
                          backgroundColor: NcstColors.slate100,
                          showCheckmark: false,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          onSelected: (val) {
                            if (val) onFilterChanged(filter);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // Search input
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by plate number, owner, or driver...',
                hintStyle: const TextStyle(fontSize: 13, color: NcstColors.slate400),
                prefixIcon: const Icon(Icons.search, size: 18, color: NcstColors.slate400),
                isDense: true,
                filled: true,
                fillColor: NcstColors.slate50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: NcstColors.slate200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: NcstColors.slate200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: NcstColors.navy),
                ),
              ),
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 16),

            // Table / List of Entries
            if (logs.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: const Text(
                  'No entries found for this filter.',
                  style: TextStyle(color: NcstColors.slate400, fontSize: 13),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: logs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  return AuditLogItemRow(log: logs[index]);
                },
              ),
          ],
        ),
      ),
    );
  }
}
