import 'dart:math' as math;

enum TimePadPart { hour, minute }

enum TimePadPeriod { am, pm }

class TimePadEntry {
  static const int minutesPerDay = 1440;

  final bool use24h;
  final int initialMinute;
  final int? periodAfter;
  final int hour;
  final int minute;
  final TimePadPart active;
  final String pending;
  final String hourTyped;
  final String minuteTyped;
  final TimePadPeriod period;
  final bool periodChosen;
  final bool awaitingPeriod;
  final bool isComplete;

  const TimePadEntry._({
    required this.use24h,
    required this.initialMinute,
    required this.periodAfter,
    required this.hour,
    required this.minute,
    required this.active,
    required this.pending,
    required this.hourTyped,
    required this.minuteTyped,
    required this.period,
    required this.periodChosen,
    required this.awaitingPeriod,
    required this.isComplete,
  });

  factory TimePadEntry.open({
    required int initialMinute,
    required bool use24h,
    int? periodAfter,
  }) {
    final start = _normalize(initialMinute);
    final hour = start ~/ 60;
    return TimePadEntry._(
      use24h: use24h,
      initialMinute: start,
      periodAfter: periodAfter == null ? null : _normalize(periodAfter),
      hour: hour,
      minute: start % 60,
      active: TimePadPart.hour,
      pending: '',
      hourTyped: '',
      minuteTyped: '',
      period: _periodOf(hour),
      periodChosen: false,
      awaitingPeriod: false,
      isComplete: false,
    );
  }

  int get value => hour * 60 + minute;

  bool get hourTouched => hourTyped.isNotEmpty;

  bool get periodIsSuggestion => !use24h && hourTouched && !periodChosen;

  String get hourLabel => use24h ? _twoDigits(hour) : '${_to12(hour)}';

  String get minuteLabel => _twoDigits(minute);

  int get previewValue {
    var h = hour;
    var m = minute;
    if (active == TimePadPart.hour && pending.isNotEmpty) {
      final typed = int.parse(pending);
      if (use24h) {
        h = typed;
      } else if (typed >= 1) {
        h = _to24(typed, periodChosen ? period : _suggestPeriod(typed, m));
      }
    }
    if (active == TimePadPart.minute && pending.isNotEmpty) {
      m = int.parse(pending) * 10;
    }
    return h * 60 + m;
  }

  bool canPressDigit(int digit) {
    if (awaitingPeriod || isComplete) return false;
    if (active == TimePadPart.minute) return pending.isNotEmpty || digit <= 5;
    return _extendsHour(digit) || _spillsIntoMinutes(digit);
  }

  bool get canPressShortcut =>
      !awaitingPeriod && !isComplete && !_lonePendingZeroHour;

  bool get canFinish => !isComplete && !_lonePendingZeroHour;

  bool get canBackspace =>
      !isComplete &&
      (awaitingPeriod || pending.isNotEmpty || active == TimePadPart.minute);

  TimePadEntry pressDigit(int digit) {
    if (!canPressDigit(digit)) return this;
    if (active == TimePadPart.minute) {
      final typed = '$pending$digit';
      if (typed.length < 2) return _copy(pending: typed);
      return _copy(
        minute: int.parse(typed),
        minuteTyped: typed,
        pending: '',
      )._settled()._finishIfReady();
    }
    if (!_extendsHour(digit)) {
      return _commitHour(
        pending,
      )._copy(active: TimePadPart.minute, pending: '$digit');
    }
    final typed = '$pending$digit';
    final standsAlone = digit >= (use24h ? 3 : 2);
    if (typed.length == 2 || standsAlone) {
      return _commitHour(typed)._copy(active: TimePadPart.minute);
    }
    return _copy(pending: typed);
  }

  TimePadEntry pressShortcut(int shortcutMinute) {
    if (!canPressShortcut) return this;
    final base = active == TimePadPart.hour && pending.isNotEmpty
        ? _commitHour(pending)
        : this;
    return base
        ._copy(
          minute: shortcutMinute,
          minuteTyped: '',
          pending: '',
          active: TimePadPart.minute,
        )
        ._settled()
        ._finishIfReady();
  }

  TimePadEntry backspace() {
    if (!canBackspace) return this;
    if (awaitingPeriod) {
      return _copy(
        awaitingPeriod: false,
        pending: minuteTyped.length == 2 ? minuteTyped.substring(0, 1) : '',
        minuteTyped: '',
        minute: initialMinute % 60,
      );
    }
    if (pending.isNotEmpty) {
      return _copy(pending: pending.substring(0, pending.length - 1));
    }
    final initialHour = initialMinute ~/ 60;
    return _copy(
      active: TimePadPart.hour,
      pending: hourTyped.length == 2 ? hourTyped.substring(0, 1) : '',
      hourTyped: '',
      hour: initialHour,
      period: periodChosen ? period : _periodOf(initialHour),
    )._settled();
  }

  TimePadEntry selectPart(TimePadPart part) {
    if (isComplete) return this;
    if (part == active && pending.isEmpty && !awaitingPeriod) return this;
    var base = this;
    if (part == TimePadPart.minute &&
        active == TimePadPart.hour &&
        pending.isNotEmpty) {
      if (_lonePendingZeroHour) return this;
      base = _commitHour(pending);
    }
    return base._copy(active: part, pending: '', awaitingPeriod: false);
  }

  TimePadEntry pressPeriod(TimePadPeriod chosen) {
    if (use24h || isComplete) return this;
    final next = _copy(period: chosen, periodChosen: true)._settled();
    if (!awaitingPeriod) return next;
    return next._copy(awaitingPeriod: false, isComplete: true);
  }

  TimePadEntry finish() {
    if (!canFinish) return this;
    var next = active == TimePadPart.hour && pending.isNotEmpty
        ? _commitHour(pending)
        : this;
    if (next.active == TimePadPart.minute && next.pending.isNotEmpty) {
      next = next._copy(
        minute: int.parse(next.pending) * 10,
        minuteTyped: next.pending,
        pending: '',
      );
    }
    return next._settled()._copy(awaitingPeriod: false, isComplete: true);
  }

  bool get _lonePendingZeroHour =>
      !use24h && active == TimePadPart.hour && pending == '0';

  bool _extendsHour(int digit) {
    if (pending.isEmpty) return true;
    if (use24h) {
      if (pending == '2') return digit <= 3;
      return pending == '0' || pending == '1';
    }
    if (pending == '0') return digit >= 1;
    if (pending == '1') return digit <= 2;
    return false;
  }

  bool _spillsIntoMinutes(int digit) {
    if (pending.isEmpty || digit > 5) return false;
    return use24h || int.parse(pending) >= 1;
  }

  TimePadEntry _commitHour(String typed) {
    if (use24h) {
      return _copy(hour: int.parse(typed), hourTyped: typed, pending: '');
    }
    return _copy(hourTyped: typed, pending: '')._settled();
  }

  TimePadEntry _settled() {
    if (use24h) return this;
    final twelve = hourTouched ? int.parse(hourTyped) : _to12(hour);
    final resolved = hourTouched && !periodChosen
        ? _suggestPeriod(twelve, minute)
        : period;
    return _copy(period: resolved, hour: _to24(twelve, resolved));
  }

  TimePadEntry _finishIfReady() {
    if (!use24h && hourTouched && !periodChosen) {
      return _copy(awaitingPeriod: true, active: TimePadPart.minute);
    }
    return _copy(isComplete: true);
  }

  TimePadPeriod _suggestPeriod(int twelve, int atMinute) {
    final am = _to24(twelve, TimePadPeriod.am) * 60 + atMinute;
    final pm = _to24(twelve, TimePadPeriod.pm) * 60 + atMinute;
    final after = periodAfter;
    if (after != null) {
      return _forwardGap(after, am) <= _forwardGap(after, pm)
          ? TimePadPeriod.am
          : TimePadPeriod.pm;
    }
    return _circularGap(initialMinute, am) <= _circularGap(initialMinute, pm)
        ? TimePadPeriod.am
        : TimePadPeriod.pm;
  }

  TimePadEntry _copy({
    int? hour,
    int? minute,
    TimePadPart? active,
    String? pending,
    String? hourTyped,
    String? minuteTyped,
    TimePadPeriod? period,
    bool? periodChosen,
    bool? awaitingPeriod,
    bool? isComplete,
  }) {
    return TimePadEntry._(
      use24h: use24h,
      initialMinute: initialMinute,
      periodAfter: periodAfter,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      active: active ?? this.active,
      pending: pending ?? this.pending,
      hourTyped: hourTyped ?? this.hourTyped,
      minuteTyped: minuteTyped ?? this.minuteTyped,
      period: period ?? this.period,
      periodChosen: periodChosen ?? this.periodChosen,
      awaitingPeriod: awaitingPeriod ?? this.awaitingPeriod,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  static int _normalize(int minute) => minute % minutesPerDay;

  static TimePadPeriod _periodOf(int hour) =>
      hour < 12 ? TimePadPeriod.am : TimePadPeriod.pm;

  static int _to12(int hour) => hour % 12 == 0 ? 12 : hour % 12;

  static int _to24(int twelve, TimePadPeriod period) =>
      twelve % 12 + (period == TimePadPeriod.pm ? 12 : 0);

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static int _forwardGap(int from, int to) {
    final gap = (to - from) % minutesPerDay;
    return gap == 0 ? minutesPerDay : gap;
  }

  static int _circularGap(int a, int b) {
    final gap = (a - b).abs();
    return math.min(gap, minutesPerDay - gap);
  }
}
