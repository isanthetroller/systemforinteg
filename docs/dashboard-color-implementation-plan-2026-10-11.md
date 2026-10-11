# Dashboard color implementation plan

## Scope

Dashboard presentation only: chart colors, matching legends, metric text, status badges and their light backgrounds. Preserve counts, data sources, filtering, calculations, status classification, polling, navigation and all backend behavior. Other web views and the mobile app are outside this change. Implementation completed; verification is recorded in dashboard-color-verification-2026-10-11.md.

## Current findings

- Gate Activity plots approved entries in navy (#253475) and approved exits in pale blue (#8294c5). Both are normal movements, but the similar colors make their directions harder to distinguish. Denied attempts are a separate summary count and are not plotted.
- Inside Campus is a composition chart for registered vehicles and visitor vehicles, not a chart of security status. Its segments use navy and pale blue. The metric cards lack matching segment swatches. Their original green/red utility classes are overridden to navy by workspace CSS; the Total markup still carries obsolete red styling.
- Vehicle Types uses four shades of blue for named categories. These are ordinary classifications, with no success/warning/danger meaning.
- KPI CSS makes most totals navy. The blocked total is already red, but its static emphasis can still suggest a problem when the count is zero.
- Parking occupancy already uses green, amber and red based on the existing available/nearly-full/full state. This is appropriate; preserve the existing state decisions.
- Security alerts already use red for active problems and neutral styling for zero alerts. Overtime uses amber, while overnight uses navy even though both require staff attention. Overnight parking alone does not establish a violation; the separately recorded hold does.
- Headings and links appropriately use dark navy. Secondary information uses slate; some small metadata is relatively faint and needs a contrast review.

## Proposed visual meanings

| Context | Color | Treatment |
|---|---|---|
| Approved entry | Green #15803D | Chart line/bar, entry summary and approved-entry KPI |
| Completed exit | Blue #1D4ED8 | Chart line/bar and exit summary |
| Denied or blocked activity | Red #B42336 | Positive denied/blocked counts and existing hold badges |
| Attention required | Amber #A16207 | Overtime and overnight labels, without changing their classifications |
| Registered vehicles on campus | Navy #253475 | Doughnut segment and matching legend swatch |
| Visitor vehicles on campus | Violet #7C3AED | Doughnut segment and matching legend swatch |
| Ordinary totals and vehicle categories | Navy #253475 | Neutral informational emphasis; vehicle-type bars use a consistent navy |
| No results, zero alerts, missing configuration | Slate | Calm, clearly labeled empty state |

Use dark tones for colored text and stronger fills for chart marks. Amber text should be dark amber on a pale background, rather than bright yellow text. Preserve dark headings, slate descriptions and navy links. Color should supplement labels, counts, symbols and line styles.

## Implementation sequence

1. **Define dashboard palette.** Add dashboard-scoped CSS variables and a small chart palette in the dashboard controller. Avoid changing global brand colors or Chart.js defaults used elsewhere.
2. **Update Gate Activity.** Apply green entries and blue exits in both Hourly and By Gate views. Match legend markers and summary text. Use solid versus dashed lines and different point shapes in Hourly mode. Keep the current two datasets and existing totals. Highlight denied counts red only when greater than zero.
3. **Align Inside Campus.** Apply navy/violet segments and matching labeled swatches to Registered/Visitors. Give Total neutral dark text. Keep the empty ring neutral. Replace the obsolete status color classes with explicit dashboard category styling.
4. **Simplify Vehicle Types.** Use consistent navy bars with the existing category labels and tooltips. Category counts do not warrant warning colors.
5. **Align dashboard metrics and attention text.** Use green for approved entries, navy for current occupancy and registration totals, and red for a positive blocked count. Use a neutral zero blocked state. Give overtime and overnight attention labels amber; retain red for an actual violation hold. Match occupancy text to its existing state and retain all existing capacity thresholds.
6. **Review accessibility and layout.** Check text/background contrast, visible chart marks, grayscale distinction, legend readability, focus states and narrow layouts. Keep movement and category labels explicit.
7. **Verify and deliver.** Review the diff for presentation-only changes; test with disposable fixtures, then publish using the established branch and test site workflow.

## Verification and acceptance

- Test empty, normal-traffic, visitor-only, registered-only, mixed occupancy, positive denied/blocked, overtime, overnight, hold, nearly-full, full and unset-capacity states.
- Confirm color meanings agree across chart marks, legends, summary counts and dashboard badges.
- Confirm entries/exits remain distinguishable without color; all categories and statuses remain labeled.
- Switch Hourly/By Gate repeatedly, refresh data and leave/reopen the dashboard; check for console errors and chart lifecycle regressions.
- Compare the same fixture's values before and after: totals, chart series, tooltips and classifications must be identical.
- Inspect desktop and narrow-screen rendering, reduced motion, and other views for unintended styling changes.
- Document results and capture before/after dashboard views. No database migration is needed.

## Recommendation

Keep navy as the campus brand and use status colors selectively. Green/blue describe normal gate movement, red flags an actual block or denial, and amber identifies an attention item. Composition and inventory charts should communicate categories and quantities without suggesting a security judgment.
