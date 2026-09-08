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

  /// Thumb position animation duration
  static const int thumbAnimationMs = 80;

  // ============================================================
  // SMOOTHING FACTORS
  // ============================================================
  /// Smoothing factor for small jitter (lower = smoother)
  static const double smoothingFactor = 0.12;

  /// Smoothing factor for dragging (more responsive)
  static const double dragSmoothingFactor = 0.4;

  // ============================================================
  // EDGE SNAPPING THRESHOLDS
  // ============================================================
  /// Raw progress threshold for immediate edge snap
  static const double immediateEdgeSnapThreshold = 0.001;

  /// Raw progress threshold for drag edge snap
  static const double dragEdgeSnapThreshold = 0.01;

  /// Smoothed progress threshold for near-edge snap
  static const double nearEdgeSmoothedThreshold = 0.02;

  /// Raw progress threshold for near-edge snap
  static const double nearEdgeRawThreshold = 0.05;

  /// Delta above which a change is a real move, not jitter, and the thumb
  /// takes it in one step instead of easing into it.
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
