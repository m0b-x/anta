import 'overview_period.dart';

/// What the overview hands the report when its view menu opens it: the
/// period it shows and its allowlist (D35). Carried in process for one
/// visit, never persisted and never a notifier — the report is pushed with
/// it as a constructor argument. A model, so the report's bloc never imports
/// the navigator (D36.10).
typedef ReportLook = ({OverviewPeriod period, Set<String> categoryIds});
