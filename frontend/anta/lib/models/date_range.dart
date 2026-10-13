/// An inclusive span of days, both ends date-only UTC (`DateTime.utc(y, m, d)`)
/// with `end` on or after `start`.
///
/// A record rather than Flutter's `DateTimeRange`, so a model stays free of
/// the material import and two spans compare by value with `==`, as the
/// calendar's date-only days do.
typedef DateRange = ({DateTime start, DateTime end});
