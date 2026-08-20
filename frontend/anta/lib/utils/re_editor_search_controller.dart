import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:re_editor/re_editor.dart';

/// Result states for replace operations
sealed class ReplaceResultState {
  const ReplaceResultState();
}

final class ReplaceSuccessState extends ReplaceResultState {
  final String newContent;
  final int replacementCount;
  final int cursorPosition;

  const ReplaceSuccessState({
    required this.newContent,
    required this.replacementCount,
    required this.cursorPosition,
  });
}

final class ReplaceFailureState extends ReplaceResultState {
  final String reason;

  const ReplaceFailureState(this.reason);
}

/// Search match representation for external use
class SearchMatch {
  final int start;
  final int end;
  final int lineNumber;

  const SearchMatch({
    required this.start,
    required this.end,
    required this.lineNumber,
  });

  int get length => end - start;
}

/// One row of the jump-to-match list: the match's line, a trimmed slice of
/// that line, and where inside the slice the hit sits so the UI can bold it.
class SearchMatchPreview {
  final int index;
  final int lineNumber;
  final String snippet;
  final int highlightStart;
  final int highlightEnd;
  final bool trimmedStart;
  final bool trimmedEnd;

  const SearchMatchPreview({
    required this.index,
    required this.lineNumber,
    required this.snippet,
    required this.highlightStart,
    required this.highlightEnd,
    required this.trimmedStart,
    required this.trimmedEnd,
  });
}

/// A search controller that wraps re_editor's CodeFindController
/// to leverage native search functionality for better performance.
///
/// This controller maintains the same API as the old NoteSearchController
/// so the UI doesn't need to change.
///
/// Also supports a "preview mode" for searching without CodeFindController,
/// useful when the editor is not mounted (e.g., preview mode).
class ReEditorSearchController extends ChangeNotifier {
  CodeFindController? _findController;
  CodeLineEditingController? _editingController;
  bool _findControllerDisposed = false;

  bool _isSearching = false;
  bool _showReplace = false;
  bool _wholeWord = false;
  bool _caseSensitive = false;
  int _lastReplacementCount = 0;

  // Track options locally since CodeFindController doesn't expose wholeWord
  String _currentQuery = '';
  String _replacement = '';

  // Preview mode search state (when no CodeFindController)
  String _previewContent = '';
  List<SearchMatch> _previewMatches = [];
  int _previewMatchIndex = -1;

  // Debounce timer for preview mode search
  Timer? _searchDebounceTimer;
  static const _searchDebounceMs = 300;

  // Cache for the converted match list, keyed on find-result identity
  CodeFindResult? _cachedMatchesResult;
  List<SearchMatch>? _cachedMatches;

  // Snippet window used by [previewAt] for long lines
  static const int _snippetMaxLength = 140;
  static const int _snippetLeadingContext = 40;

  bool get _hasFindController =>
      _findController != null && !_findControllerDisposed;

  /// Set the CodeFindController from findBuilder callback
  /// This should be called from the findBuilder in CodeEditor
  void setFindController(CodeFindController controller) {
    if (_findController != controller) {
      _findController?.removeListener(_onFindControllerChanged);
      _findController = controller;
      _findControllerDisposed = false;
      _findController!.addListener(_onFindControllerChanged);

      // Restore search state if there's an active search
      if (_isSearching && _currentQuery.isNotEmpty) {
        // Need to activate find mode first, then set the query
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (_findController != null && !_findControllerDisposed) {
            _findController!.findMode();
            _findController!.findInputController.text = _applyWholeWord(
              _currentQuery,
            );
            // Also restore case sensitivity if it was set
            if (_caseSensitive) {
              final value = _findController!.value;
              if (!(value?.option.caseSensitive ?? false)) {
                _findController!.toggleCaseSensitive();
              }
            }
            notifyListeners();
          }
        });
      } else {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      }
    }
  }

  void clearFindController() {
    _findController?.removeListener(_onFindControllerChanged);
    _findController = null;
    _findControllerDisposed = true;
    _invalidateMatchCache();
  }

  void _invalidateMatchCache() {
    _cachedMatchesResult = null;
    _cachedMatches = null;
  }

  /// Initialize with the editing controller (for offset calculations)
  void initialize(CodeLineEditingController editingController) {
    _editingController = editingController;
  }

  void _onFindControllerChanged() {
    notifyListeners();
  }

  /// The underlying CodeFindController for use with findBuilder
  CodeFindController? get findController => _findController;

  /// Current search query
  String get query => _currentQuery;

  /// Replacement text
  String get replacement => _replacement;

  /// List of matches converted to SearchMatch format.
  ///
  /// Converted with one prefix-sum pass over the lines and cached until the
  /// result carries a different match list or document: this runs on every
  /// search notification, and the naive form walked all lines per match.
  List<SearchMatch> get matches {
    // Use native CodeFindController if available
    if (_hasFindController) {
      final result = _findController?.value?.result;
      if (result == null) return const [];

      final cached = _cachedMatches;
      final cachedFor = _cachedMatchesResult;
      if (cached != null &&
          cachedFor != null &&
          identical(cachedFor.matches, result.matches) &&
          identical(cachedFor.codeLines, result.codeLines)) {
        return cached;
      }

      final starts = _lineStartOffsets();
      final converted = <SearchMatch>[
        for (final match in result.matches)
          SearchMatch(
            start: _offsetAt(starts, match.start),
            end: _offsetAt(starts, match.end),
            lineNumber: match.startIndex,
          ),
      ];
      _cachedMatchesResult = result;
      _cachedMatches = converted;
      return converted;
    }

    // Use preview mode matches
    return _previewMatches;
  }

  List<int> _lineStartOffsets() {
    final lines = _editingController?.codeLines;
    if (lines == null) return const [0];
    final starts = List<int>.filled(lines.length + 1, 0);
    var offset = 0;
    for (var i = 0; i < lines.length; i++) {
      starts[i] = offset;
      offset += lines[i].text.length + 1; // +1 for newline
    }
    starts[lines.length] = offset;
    return starts;
  }

  int _offsetAt(List<int> starts, CodeLinePosition pos) {
    if (pos.index < 0) return pos.offset;
    if (pos.index >= starts.length) return starts.last;
    return starts[pos.index] + pos.offset;
  }

  int _selectionToOffset(CodeLinePosition pos) {
    if (_editingController == null) return 0;
    final lines = _editingController!.codeLines;
    int offset = 0;
    for (int i = 0; i < pos.index && i < lines.length; i++) {
      offset += lines[i].text.length + 1; // +1 for newline
    }
    return offset + pos.offset;
  }

  /// Current match index (0-based)
  int get currentMatchIndex {
    if (_hasFindController) {
      final value = _findController?.value;
      return value?.result?.index ?? -1;
    }
    return _previewMatchIndex;
  }

  /// Total number of matches
  int get matchCount {
    if (_hasFindController) {
      final value = _findController?.value;
      return value?.result?.matches.length ?? 0;
    }
    return _previewMatches.length;
  }

  /// Whether there are any matches
  bool get hasMatches => matchCount > 0;

  /// Whether there might be more matches (re_editor doesn't limit)
  bool get hasMoreMatches => false;

  /// Case sensitive search option
  bool get caseSensitive {
    if (_hasFindController) {
      final value = _findController?.value;
      return value?.option.caseSensitive ?? false;
    }
    return _caseSensitive;
  }

  /// Regex search option
  bool get useRegex {
    if (!_hasFindController) return false;
    final value = _findController?.value;
    return value?.option.regex ?? false;
  }

  /// Whole word search option (handled locally)
  bool get wholeWord => _wholeWord;

  /// Whether search is currently active
  bool get isSearching => _isSearching;

  /// Whether replace panel should be shown
  bool get showReplace => _showReplace;

  /// Last replacement count
  int get lastReplacementCount => _lastReplacementCount;

  /// Get the current match
  SearchMatch? get currentMatch {
    if (_hasFindController) {
      final value = _findController?.value;
      if (value?.result == null || value!.result!.matches.isEmpty) return null;

      final idx = value.result!.index;
      if (idx < 0 || idx >= value.result!.matches.length) return null;

      final match = value.result!.matches[idx];
      return SearchMatch(
        start: _selectionToOffset(match.start),
        end: _selectionToOffset(match.end),
        lineNumber: match.startIndex,
      );
    }

    // Preview mode
    if (_previewMatchIndex >= 0 &&
        _previewMatchIndex < _previewMatches.length) {
      return _previewMatches[_previewMatchIndex];
    }
    return null;
  }

  /// Whether a search is pending (re_editor handles this internally)
  bool get isSearchPending {
    if (!_hasFindController) return false;
    final value = _findController?.value;
    return value?.searching ?? false;
  }

  /// Update content for preview mode search
  /// Only performs search if we're actively searching to avoid unnecessary CPU usage
  void updateContent(String content) {
    if (identical(_previewContent, content) || _previewContent == content) {
      return;
    }
    _previewContent = content;
    // Only re-run preview search if we're actively searching
    if (_isSearching && _currentQuery.isNotEmpty) {
      _performPreviewSearch();
      // Only notify if we're not using the find controller
      // (otherwise the UI would show incorrect results)
      if (!_hasFindController) {
        notifyListeners();
      }
    }
  }

  /// Perform text search for preview mode
  void _performPreviewSearch() {
    if (_currentQuery.isEmpty) {
      _previewMatches = [];
      _previewMatchIndex = -1;
      return;
    }

    final searchText = _caseSensitive
        ? _previewContent
        : _previewContent.toLowerCase();
    final searchQuery = _caseSensitive
        ? _currentQuery
        : _currentQuery.toLowerCase();

    final matches = <SearchMatch>[];
    int index = 0;
    int lineNumber = 0;

    while (true) {
      index = searchText.indexOf(searchQuery, index);
      if (index == -1) break;

      // Calculate line number
      lineNumber = '\n'.allMatches(_previewContent.substring(0, index)).length;

      matches.add(
        SearchMatch(
          start: index,
          end: index + _currentQuery.length,
          lineNumber: lineNumber,
        ),
      );
      index += _currentQuery.length;
    }

    _previewMatches = matches;
    _previewMatchIndex = matches.isNotEmpty ? 0 : -1;
  }

  /// Search with the given query (debounced for preview mode)
  void search(String query) {
    _currentQuery = query;
    if (_hasFindController) {
      // Editor mode - use CodeFindController directly (already handles its own updates)
      _findController?.findInputController.text = _applyWholeWord(query);
    } else {
      // Preview mode - debounce to avoid searching on every keystroke
      _searchDebounceTimer?.cancel();
      _searchDebounceTimer = Timer(
        Duration(milliseconds: _searchDebounceMs),
        () {
          _performPreviewSearch();
          notifyListeners();
        },
      );
    }
  }

  /// Execute search immediately without debouncing
  void searchImmediate(String query) {
    _currentQuery = query;
    _searchDebounceTimer?.cancel();
    if (_hasFindController) {
      _findController?.findInputController.text = _applyWholeWord(query);
    } else {
      _performPreviewSearch();
      notifyListeners();
    }
  }

  String _applyWholeWord(String query) {
    if (_wholeWord && query.isNotEmpty && !useRegex) {
      // Wrap with word boundaries for whole word matching
      return '\\b${RegExp.escape(query)}\\b';
    }
    return query;
  }

  /// Update replacement text
  void updateReplacement(String replacement) {
    _replacement = replacement;
    if (_hasFindController) {
      _findController?.replaceInputController.text = replacement;
    }
  }

  /// Toggle case sensitivity
  void toggleCaseSensitive() {
    if (_hasFindController) {
      _findController?.toggleCaseSensitive();
    } else {
      _caseSensitive = !_caseSensitive;
      _performPreviewSearch();
    }
    notifyListeners();
  }

  /// Toggle regex mode
  void toggleRegex() {
    if (_hasFindController) {
      _findController?.toggleRegex();
    }
    // Re-apply whole word if needed after regex toggle
    if (_currentQuery.isNotEmpty) {
      search(_currentQuery);
    }
    notifyListeners();
  }

  /// Toggle whole word matching
  void toggleWholeWord() {
    _wholeWord = !_wholeWord;
    // Re-apply search with whole word
    if (_currentQuery.isNotEmpty && _hasFindController) {
      _findController?.findInputController.text = _applyWholeWord(
        _currentQuery,
      );
    }
    notifyListeners();
  }

  /// Toggle show replace panel
  void toggleShowReplace() {
    _showReplace = !_showReplace;
    if (_hasFindController) {
      if (_showReplace) {
        _findController?.replaceMode();
      } else {
        _findController?.findMode();
      }
    }
    notifyListeners();
  }

  /// Open search
  void openSearch() {
    _isSearching = true;
    _lastReplacementCount = 0;
    if (_hasFindController) {
      _findController?.findMode();
    }
    notifyListeners();
  }

  /// Close search
  void closeSearch() {
    _isSearching = false;
    _showReplace = false;
    _replacement = '';
    _currentQuery = '';
    _previewMatches = [];
    _previewMatchIndex = -1;
    _invalidateMatchCache();
    if (_hasFindController) {
      _findController?.close();
    }
    notifyListeners();
  }

  /// Navigate to next match
  void nextMatch() {
    if (_hasFindController) {
      _findController?.nextMatch();
    } else if (_previewMatches.isNotEmpty) {
      _previewMatchIndex = (_previewMatchIndex + 1) % _previewMatches.length;
      notifyListeners();
    }
  }

  /// Navigate to previous match
  void previousMatch() {
    if (_hasFindController) {
      _findController?.previousMatch();
    } else if (_previewMatches.isNotEmpty) {
      _previewMatchIndex =
          (_previewMatchIndex - 1 + _previewMatches.length) %
          _previewMatches.length;
      notifyListeners();
    }
  }

  /// Go to specific match index
  void goToMatch(int index) {
    if (_hasFindController) {
      _findController?.goToMatch(index);
    } else if (index >= 0 && index < _previewMatches.length) {
      _previewMatchIndex = index;
      notifyListeners();
    }
  }

  /// Line slice around the match at [index], built on demand so a jump-to-match
  /// list can render thousands of hits without materializing every snippet.
  SearchMatchPreview? previewAt(int index) {
    if (index < 0 || index >= matchCount) return null;

    final String lineText;
    final int lineNumber;
    int startInLine;
    int endInLine;

    if (_hasFindController) {
      final result = _findController?.value?.result;
      if (result == null || index >= result.matches.length) return null;
      final lines = _editingController?.codeLines;
      final match = result.matches[index];
      if (lines == null || match.startIndex >= lines.length) return null;
      lineNumber = match.startIndex;
      lineText = lines[match.startIndex].text;
      startInLine = match.startOffset;
      endInLine = match.endIndex == match.startIndex
          ? match.endOffset
          : lineText.length;
    } else {
      final match = _previewMatches[index];
      final content = _previewContent;
      if (match.start > content.length) return null;
      final lineStart = match.start == 0
          ? 0
          : content.lastIndexOf('\n', match.start - 1) + 1;
      final newline = content.indexOf('\n', match.start);
      final lineEnd = newline == -1 ? content.length : newline;
      lineNumber = match.lineNumber;
      lineText = content.substring(lineStart, lineEnd);
      startInLine = match.start - lineStart;
      endInLine = match.end - lineStart;
    }

    startInLine = startInLine.clamp(0, lineText.length);
    endInLine = endInLine.clamp(startInLine, lineText.length);

    var sliceStart = 0;
    var sliceEnd = lineText.length;
    if (lineText.length > _snippetMaxLength) {
      sliceStart = max(0, startInLine - _snippetLeadingContext);
      sliceEnd = min(lineText.length, sliceStart + _snippetMaxLength);
      sliceStart = max(0, min(sliceStart, sliceEnd - _snippetMaxLength));
    }

    final snippet = lineText.substring(sliceStart, sliceEnd);
    return SearchMatchPreview(
      index: index,
      lineNumber: lineNumber,
      snippet: snippet,
      highlightStart: (startInLine - sliceStart).clamp(0, snippet.length),
      highlightEnd: (endInLine - sliceStart).clamp(0, snippet.length),
      trimmedStart: sliceStart > 0,
      trimmedEnd: sliceEnd < lineText.length,
    );
  }

  /// Replace current match
  ReplaceResultState replaceCurrent() {
    if (!hasMatches || !_hasFindController) {
      return const ReplaceFailureState('No match selected');
    }

    _findController!.replaceInputController.text = _replacement;
    _findController!.replaceMatch();
    _lastReplacementCount = 1;

    return ReplaceSuccessState(
      newContent: _editingController?.text ?? '',
      replacementCount: 1,
      cursorPosition: 0,
    );
  }

  /// Replace all matches
  ReplaceResultState replaceAll() {
    if (!hasMatches || !_hasFindController) {
      return const ReplaceFailureState('No matches to replace');
    }

    final count = matchCount;
    _findController!.replaceInputController.text = _replacement;
    _findController!.replaceAllMatches();
    _lastReplacementCount = count;

    return ReplaceSuccessState(
      newContent: _editingController?.text ?? '',
      replacementCount: count,
      cursorPosition: 0,
    );
  }

  /// Replace current match and return new content (legacy API)
  String? replaceCurrentMatch(String replacement) {
    _replacement = replacement;
    final result = replaceCurrent();
    if (result is ReplaceSuccessState) {
      return result.newContent;
    }
    return null;
  }

  /// Replace all matches and return new content (legacy API)
  String replaceAllMatches(String replacement) {
    _replacement = replacement;
    final result = replaceAll();
    if (result is ReplaceSuccessState) {
      return result.newContent;
    }
    return _editingController?.text ?? '';
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _findController?.removeListener(_onFindControllerChanged);
    // Don't dispose _findController - it's owned by CodeEditor
    super.dispose();
  }
}
