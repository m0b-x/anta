/// Constants for scroll progress indicator
class ScrollIndicatorConstants {
  ScrollIndicatorConstants._();

  // ============================================================
  // SIZE CONSTANTS
  // ============================================================
  /// Default visible width of the scrollbar
  static const double visibleWidth = 6.0;

  /// Touch area width (iOS recommended touch target)
  static const double touchAreaWidth = 44.0;

  /// Default thumb height
  static const double defaultThumbHeight = 40.0;

  /// Minimum thumb height
  static const double minThumbHeight = 30.0;

  /// Maximum thumb height
  static const double maxThumbHeight = 80.0;

  /// Thumb height as percentage of track (0.15 = 15%)
  static const double thumbHeightPercentage = 0.15;

  /// Margin from the right edge
  static const double rightMargin = 2.0;

  // ============================================================
  // TIMING CONSTANTS (in milliseconds)
  // ============================================================
  /// Animation duration for bar width changes
  static const int animationDurationMs = 150;

  /// Duration the scrollbar stays expanded after scrolling
  static const int collapseDelayMs = 1200;

  /// Interval for checking scroll metrics changes
  static const int metricsCheckIntervalMs = 100;

  /// Thumb colour and shadow animation duration (its geometry is laid
  /// out, not animated)
  static const int thumbAnimationMs = 80;

  // ============================================================
  // SMOOTHING FACTORS
  // ============================================================
  /// Smoothing factor for small jitter (lower = smoother)
  static const double smoothingFactor = 0.12;

  /// Remaining distance (fraction of the track) below which the smoothed
  /// thumb is considered settled and lands on the exact position.
  static const double settleTolerance = 0.002;

  /// Frames the filter may spend settling without a scroll notification
  /// before it lands on the exact position outright. From the largest lag
  /// it can hold it converges in about 35, so this never fires in normal
  /// use; it bounds the loop if the target ever kept drifting.
  static const int maxSettleFrames = 60;

  // ============================================================
  // EDGE SNAPPING THRESHOLDS
  // ============================================================
  /// Raw progress threshold for immediate edge snap
  static const double immediateEdgeSnapThreshold = 0.001;

  /// A change in the scroll offset between two readings larger than this
  /// fraction of the content is a discontinuity — a jump, a restore, a
  /// search hit — and the thumb takes it in one step instead of easing.
  static const double fastSmoothingDeltaThreshold = 0.15;

  // ============================================================
  // OPACITY VALUES
  // ============================================================
  /// Thumb opacity when expanded (not dragging)
  static const double expandedThumbOpacity = 0.8;

  /// Thumb opacity when idle
  static const double idleThumbOpacity = 0.5;

  /// Track opacity when expanded/dragging
  static const double expandedTrackOpacity = 0.15;

  /// Track opacity when idle
  static const double idleTrackOpacity = 0.08;

  /// Shadow opacity when dragging
  static const double dragShadowOpacity = 0.4;

  // ============================================================
  // EXPANSION MULTIPLIER
  // ============================================================
  /// Width multiplier when expanded
  static const double expandedWidthMultiplier = 1.5;

  // ============================================================
  // SHADOW CONSTANTS
  // ============================================================
  /// Blur radius for drag shadow
  static const double dragShadowBlurRadius = 6.0;

  /// Spread radius for drag shadow
  static const double dragShadowSpreadRadius = 1.0;
}
