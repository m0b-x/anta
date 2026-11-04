import 'package:intl/intl.dart';

import '../constants/category_kinds.dart';
import '../l10n/app_localizations.dart';
import '../models/category_profile.dart';

// The words of a category's profile — its kind, area, measure and goal —
// as the category editor and its two sub-sheets draw them. One switch per
// enum, so a new value fails the build here rather than drawing a key.

String categoryKindName(AppLocalizations l10n, CategoryKind kind) =>
    switch (kind) {
      CategoryKind.routine => l10n.categoryKindRoutine,
      CategoryKind.workout => l10n.categoryKindWorkout,
      CategoryKind.medication => l10n.categoryKindMedication,
      CategoryKind.sleep => l10n.categoryKindSleep,
      CategoryKind.episode => l10n.categoryKindEpisode,
      CategoryKind.appointment => l10n.categoryKindAppointment,
      CategoryKind.work => l10n.categoryKindWork,
      CategoryKind.meeting => l10n.categoryKindMeeting,
      CategoryKind.task => l10n.categoryKindTask,
      CategoryKind.deadline => l10n.categoryKindDeadline,
      CategoryKind.study => l10n.categoryKindStudy,
      CategoryKind.bill => l10n.categoryKindBill,
      CategoryKind.income => l10n.categoryKindIncome,
      CategoryKind.social => l10n.categoryKindSocial,
      CategoryKind.anniversary => l10n.categoryKindAnniversary,
      CategoryKind.chore => l10n.categoryKindChore,
      CategoryKind.maintenance => l10n.categoryKindMaintenance,
      CategoryKind.expiry => l10n.categoryKindExpiry,
      CategoryKind.trip => l10n.categoryKindTrip,
      CategoryKind.leave => l10n.categoryKindLeave,
      CategoryKind.custom => l10n.categoryKindCustom,
    };

/// The kind's one line of examples — at most 28 characters in every
/// language, so the picker's two-line rows never cut one at 200 %.
String categoryKindExample(AppLocalizations l10n, CategoryKind kind) =>
    switch (kind) {
      CategoryKind.routine => l10n.categoryKindExampleRoutine,
      CategoryKind.workout => l10n.categoryKindExampleWorkout,
      CategoryKind.medication => l10n.categoryKindExampleMedication,
      CategoryKind.sleep => l10n.categoryKindExampleSleep,
      CategoryKind.episode => l10n.categoryKindExampleEpisode,
      CategoryKind.appointment => l10n.categoryKindExampleAppointment,
      CategoryKind.work => l10n.categoryKindExampleWork,
      CategoryKind.meeting => l10n.categoryKindExampleMeeting,
      CategoryKind.task => l10n.categoryKindExampleTask,
      CategoryKind.deadline => l10n.categoryKindExampleDeadline,
      CategoryKind.study => l10n.categoryKindExampleStudy,
      CategoryKind.bill => l10n.categoryKindExampleBill,
      CategoryKind.income => l10n.categoryKindExampleIncome,
      CategoryKind.social => l10n.categoryKindExampleSocial,
      CategoryKind.anniversary => l10n.categoryKindExampleAnniversary,
      CategoryKind.chore => l10n.categoryKindExampleChore,
      CategoryKind.maintenance => l10n.categoryKindExampleMaintenance,
      CategoryKind.expiry => l10n.categoryKindExampleExpiry,
      CategoryKind.trip => l10n.categoryKindExampleTrip,
      CategoryKind.leave => l10n.categoryKindExampleLeave,
      CategoryKind.custom => l10n.categoryKindExampleCustom,
    };

String lifeAreaName(AppLocalizations l10n, LifeArea area) => switch (area) {
  LifeArea.health => l10n.lifeAreaHealth,
  LifeArea.work => l10n.lifeAreaWork,
  LifeArea.money => l10n.lifeAreaMoney,
  LifeArea.people => l10n.lifeAreaPeople,
  LifeArea.home => l10n.lifeAreaHome,
  LifeArea.leisure => l10n.lifeAreaLeisure,
  LifeArea.other => l10n.lifeAreaOther,
};

/// A measure's name. The three that never lead a category (Cancelled, Lead
/// time, Timing) are not offered as a primary, but sync or a later build can
/// store one, and the Measure row then names what is stored.
String reportMeasureName(AppLocalizations l10n, ReportMeasure measure) =>
    switch (measure) {
      ReportMeasure.count => l10n.categoryMeasureCount,
      ReportMeasure.events => l10n.categoryMeasureEvents,
      ReportMeasure.hours => l10n.categoryMeasureHours,
      ReportMeasure.attendance => l10n.categoryMeasureAttendance,
      ReportMeasure.cancelled => l10n.categoryMeasureCancelled,
      ReportMeasure.tasks => l10n.categoryMeasureTasks,
      ReportMeasure.money => l10n.categoryMeasureMoney,
      ReportMeasure.lastSeen => l10n.categoryMeasureLastSeen,
      ReportMeasure.leadTime => l10n.categoryMeasureLeadTime,
      ReportMeasure.timing => l10n.categoryMeasureTiming,
      ReportMeasure.daysUntil => l10n.categoryMeasureDaysUntil,
    };

String targetPeriodName(AppLocalizations l10n, TargetPeriod period) =>
    switch (period) {
      TargetPeriod.day => l10n.categoryGoalPeriodDay,
      TargetPeriod.week => l10n.categoryGoalPeriodWeek,
      TargetPeriod.month => l10n.categoryGoalPeriodMonth,
      TargetPeriod.year => l10n.categoryGoalPeriodYear,
    };

/// A goal type's row label; Budget only ever lists on a Money primary.
String targetKindName(AppLocalizations l10n, TargetKind kind) => switch (kind) {
  TargetKind.atLeast => l10n.categoryGoalTypeAtLeast,
  TargetKind.atMost => l10n.categoryGoalTypeAtMost,
  TargetKind.budget => l10n.categoryGoalTypeBudget,
  TargetKind.maxGap => l10n.categoryGoalTypeMaxGap,
};

/// [target] in words — "At least 3 a week", "At most 40 h a week", "Budget
/// 1,200 a month", "At most 180 days between" — its stored value read in
/// [primary]'s unit. The editor's Goal caption and the goal sheet's line
/// under the value are this one function, so what the sheet says before
/// Done is what the row says after it.
///
/// The sheet stores whole hours and whole money, but sync or a later build
/// can store a part: it reads exactly ("7.5 h", "12.50"), never floored.
String categoryGoalReadBack(
  AppLocalizations l10n,
  ReportTarget target,
  ReportMeasure? primary,
) {
  final period = target.period;
  if (target.kind == TargetKind.maxGap || period == null) {
    return l10n.categoryGoalGap(target.value);
  }
  final unit = CategoryGoalLimits.unitOf(primary);
  final scale = CategoryGoalLimits.scaleOf(unit);
  final number = NumberFormat.decimalPattern(l10n.localeName);
  if (target.value % scale != 0) {
    final digits = unit == CategoryGoalUnit.money ? 2 : 1;
    number
      ..minimumFractionDigits = digits
      ..maximumFractionDigits = digits;
  }
  final shown = number.format(target.value / scale);
  final amount = switch (unit) {
    CategoryGoalUnit.hours => l10n.categoryGoalHours(shown),
    CategoryGoalUnit.tasks => l10n.categoryGoalTasks(target.value),
    _ => shown,
  };
  return switch (target.kind) {
    TargetKind.atLeast => l10n.categoryGoalAtLeast(amount, period.name),
    TargetKind.atMost => l10n.categoryGoalAtMost(amount, period.name),
    TargetKind.budget => l10n.categoryGoalBudget(amount, period.name),
    TargetKind.maxGap => l10n.categoryGoalGap(target.value),
  };
}
