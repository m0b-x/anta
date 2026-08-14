import 'package:flutter/foundation.dart';

/// Developer options configuration for debugging the app.
/// All options are disabled by default and have zero performance impact when off.
class DevOptions extends ChangeNotifier {
  // Singleton instance
  static DevOptions? _instance;
  static DevOptions get instance => _instance ??= DevOptions._();

  DevOptions._();

  // ═══════════════════════════════════════════════════════════════════════════
  // DEVELOPER MODE ACCESS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Whether developer options menu is unlocked (swipe gym icon to unlock)
  bool _developerModeUnlocked = false;
  bool get developerModeUnlocked => _developerModeUnlocked;
  set developerModeUnlocked(bool value) {
    if (_developerModeUnlocked != value) {
      _developerModeUnlocked = value;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUALIZATION / DEBUG
  // ═══════════════════════════════════════════════════════════════════════════

  /// Color different markdown blocks (headers, code, lists, etc.)
  bool _colorMarkdownBlocks = false;
  bool get colorMarkdownBlocks => _colorMarkdownBlocks;
  set colorMarkdownBlocks(bool value) {
    if (_colorMarkdownBlocks != value) {
      _colorMarkdownBlocks = value;
      notifyListeners();
    }
  }

  /// Draw borders around each parsed markdown element
  bool _showBlockBoundaries = false;
  bool get showBlockBoundaries => _showBlockBoundaries;
  set showBlockBoundaries(bool value) {
    if (_showBlockBoundaries != value) {
      _showBlockBoundaries = value;
      notifyListeners();
    }
  }

  /// Visualize whitespace characters (spaces, tabs, newlines)
  bool _showWhitespace = false;
  bool get showWhitespace => _showWhitespace;
  set showWhitespace(bool value) {
    if (_showWhitespace != value) {
      _showWhitespace = value;
      notifyListeners();
    }
  }

  /// Show line numbers in preview (mapped to source lines)
  bool _showPreviewLineNumbers = false;
  bool get showPreviewLineNumbers => _showPreviewLineNumbers;
  set showPreviewLineNumbers(bool value) {
    if (_showPreviewLineNumbers != value) {
      _showPreviewLineNumbers = value;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERFORMANCE MONITORING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Display render time for preview
  bool _showRenderTime = false;
  bool get showRenderTime => _showRenderTime;
  set showRenderTime(bool value) {
    if (_showRenderTime != value) {
      _showRenderTime = value;
      notifyListeners();
    }
  }

  /// Show FPS counter overlay
  bool _showFpsCounter = false;
  bool get showFpsCounter => _showFpsCounter;
  set showFpsCounter(bool value) {
    if (_showFpsCounter != value) {
      _showFpsCounter = value;
      notifyListeners();
    }
  }

  /// Highlight which chunks are currently loaded in preview
  bool _showChunkIndicators = false;
  bool get showChunkIndicators => _showChunkIndicators;
  set showChunkIndicators(bool value) {
    if (_showChunkIndicators != value) {
      _showChunkIndicators = value;
      notifyListeners();
    }
  }

  /// Show repaint rainbow (colors widgets when they repaint)
  bool _showRepaintRainbow = false;
  bool get showRepaintRainbow => _showRepaintRainbow;
  set showRepaintRainbow(bool value) {
    if (_showRepaintRainbow != value) {
      _showRepaintRainbow = value;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EDITOR DEBUG
  // ═══════════════════════════════════════════════════════════════════════════

  /// Show cursor position info (line, column, offset)
  bool _showCursorInfo = false;
  bool get showCursorInfo => _showCursorInfo;
  set showCursorInfo(bool value) {
    if (_showCursorInfo != value) {
      _showCursorInfo = value;
      notifyListeners();
    }
  }

  /// Show selection details (start, end, length)
  bool _showSelectionDetails = false;
  bool get showSelectionDetails => _showSelectionDetails;
  set showSelectionDetails(bool value) {
    if (_showSelectionDetails != value) {
      _showSelectionDetails = value;
      notifyListeners();
    }
  }

  /// Log parser events to debug console
  bool _logParserEvents = false;
  bool get logParserEvents => _logParserEvents;
  set logParserEvents(bool value) {
    if (_logParserEvents != value) {
      _logParserEvents = value;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STORAGE / DATA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Show note size in bytes
  bool _showNoteSize = false;
  bool get showNoteSize => _showNoteSize;
  set showNoteSize(bool value) {
    if (_showNoteSize != value) {
      _showNoteSize = value;
      notifyListeners();
    }
  }

  /// Show database statistics (query count, cache hits)
  bool _showDatabaseStats = false;
  bool get showDatabaseStats => _showDatabaseStats;
  set showDatabaseStats(bool value) {
    if (_showDatabaseStats != value) {
      _showDatabaseStats = value;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if any dev option is enabled
  bool get anyEnabled =>
      _colorMarkdownBlocks ||
      _showBlockBoundaries ||
      _showWhitespace ||
      _showPreviewLineNumbers ||
      _showRenderTime ||
      _showFpsCounter ||
      _showChunkIndicators ||
      _showRepaintRainbow ||
      _showCursorInfo ||
      _showSelectionDetails ||
      _logParserEvents ||
      _showNoteSize ||
      _showDatabaseStats;

  /// Reset all options to default (disabled)
  /// Note: Does NOT reset developerModeUnlocked - use lockDeveloperMode() for that
  void resetAll() {
    _colorMarkdownBlocks = false;
    _showBlockBoundaries = false;
    _showWhitespace = false;
    _showPreviewLineNumbers = false;
    _showRenderTime = false;
    _showFpsCounter = false;
    _showChunkIndicators = false;
    _showRepaintRainbow = false;
    _showCursorInfo = false;
    _showSelectionDetails = false;
    _logParserEvents = false;
    _showNoteSize = false;
    _showDatabaseStats = false;
    notifyListeners();
  }

  /// Lock developer mode and reset all options
  void lockDeveloperMode() {
    _developerModeUnlocked = false;
    resetAll();
  }

  /// Load options from a map (for persistence)
  void loadFromMap(Map<String, bool> map) {
    _developerModeUnlocked = map['developerModeUnlocked'] ?? false;
    _colorMarkdownBlocks = map['colorMarkdownBlocks'] ?? false;
    _showBlockBoundaries = map['showBlockBoundaries'] ?? false;
    _showWhitespace = map['showWhitespace'] ?? false;
    _showPreviewLineNumbers = map['showPreviewLineNumbers'] ?? false;
    _showRenderTime = map['showRenderTime'] ?? false;
    _showFpsCounter = map['showFpsCounter'] ?? false;
    _showChunkIndicators = map['showChunkIndicators'] ?? false;
    _showRepaintRainbow = map['showRepaintRainbow'] ?? false;
    _showCursorInfo = map['showCursorInfo'] ?? false;
    _showSelectionDetails = map['showSelectionDetails'] ?? false;
    _logParserEvents = map['logParserEvents'] ?? false;
    _showNoteSize = map['showNoteSize'] ?? false;
    _showDatabaseStats = map['showDatabaseStats'] ?? false;
    notifyListeners();
  }

  /// Convert to map for persistence
  Map<String, bool> toMap() => {
    'developerModeUnlocked': _developerModeUnlocked,
    'colorMarkdownBlocks': _colorMarkdownBlocks,
    'showBlockBoundaries': _showBlockBoundaries,
    'showWhitespace': _showWhitespace,
    'showPreviewLineNumbers': _showPreviewLineNumbers,
    'showRenderTime': _showRenderTime,
    'showFpsCounter': _showFpsCounter,
    'showChunkIndicators': _showChunkIndicators,
    'showRepaintRainbow': _showRepaintRainbow,
    'showCursorInfo': _showCursorInfo,
    'showSelectionDetails': _showSelectionDetails,
    'logParserEvents': _logParserEvents,
    'showNoteSize': _showNoteSize,
    'showDatabaseStats': _showDatabaseStats,
  };
}
