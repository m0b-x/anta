import 'package:equatable/equatable.dart';

import '../../bloc/calendar/calendar_state.dart';
import '../../models/overview_period.dart';
import '../../models/report_look.dart';

sealed class ReportEvent extends Equatable {
  const ReportEvent();

  @override
  List<Object?> get props => [];
}

/// The page has opened: read what the report remembers, then fold once the
/// calendar has loaded. [look] is the overview's period and allowlist when
/// its view menu opened the report (D35), and wins over the stored ones.
final class ReportOpened extends ReportEvent {
  final ReportLook? look;

  const ReportOpened({this.look});

  @override
  List<Object?> get props => [look?.period, look?.categoryIds];
}

/// The calendar bloc emitted a loaded state: a refold when its events or a
/// revision moved, nothing otherwise. The bloc folds the calendar's newest
/// state, not [calendar], so a burst of marks queued behind a fold folds
/// once, at its end.
final class ReportCalendarChanged extends ReportEvent {
  final CalendarPageLoaded calendar;

  const ReportCalendarChanged(this.calendar);

  // Identity, never a value compare: the calendar's states carry every
  // event, and two loaded states are compared by what they hold anyway.
  @override
  List<Object?> get props => [identityHashCode(calendar)];
}

/// A Period menu row or the range picker's span: the new home, persisted
/// when it is a kept kind — a relative row (Last / Next week or month) as
/// its base preset, which the report reopens on (D36.2).
final class ReportPeriodPicked extends ReportEvent {
  final OverviewPeriod period;

  const ReportPeriodPicked(this.period);

  @override
  List<Object?> get props => [period];
}

/// ◄ (`direction < 0`) or ►: a look at the neighbouring period, never
/// persisted and never the home.
final class ReportStepped extends ReportEvent {
  final int direction;

  const ReportStepped(this.direction);

  @override
  List<Object?> get props => [direction];
}

/// The band's Today slot: back to the period as picked.
final class ReportHomePressed extends ReportEvent {
  const ReportHomePressed();
}

/// The bar's Categories picker answered; empty is every category.
final class ReportCategoriesPicked extends ReportEvent {
  final Set<String> categoryIds;

  const ReportCategoriesPicked(this.categoryIds);

  @override
  List<Object?> get props => [categoryIds];
}

/// The wall clock moved to another day while the page was open: the periods
/// holding today move on, and the rest of [ReportResumed] is asked too.
final class ReportDayChanged extends ReportEvent {
  final DateTime today;

  const ReportDayChanged(this.today);

  @override
  List<Object?> get props => [today];
}

/// The app came back to the front or a page above closed. Holidays and the
/// category catalogue change with no calendar event (D32), and the week
/// start may have moved in the settings, so the report asks again; the
/// service's memo answers when nothing it reads has moved.
final class ReportResumed extends ReportEvent {
  const ReportResumed();
}
