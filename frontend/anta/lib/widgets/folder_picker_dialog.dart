import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../constants/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../models/folder.dart';
import '../services/app_navigator.dart';
import '../services/folder_name_index.dart';
import '../services/folder_storage_service.dart';
import '../services/recent_destinations_service.dart';

/// Show the folder picker dialog and return:
///   - `null` if the user cancels;
///   - `''` (empty string) for the root folder;
///   - the folder id of the chosen folder otherwise.
Future<String?> showFolderPickerDialog(
  BuildContext context, {
  required String currentFolderId,
  Set<String>? excludeFolderIds,
  bool allowRoot = true,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FolderPickerDialog(
      currentFolderId: currentFolderId,
      excludeFolderIds: excludeFolderIds ?? const {},
      allowRoot: allowRoot,
    ),
  );
}

class _FolderPickerDialog extends StatefulWidget {
  final String currentFolderId;
  final Set<String> excludeFolderIds;
  final bool allowRoot;

  const _FolderPickerDialog({
    required this.currentFolderId,
    required this.excludeFolderIds,
    required this.allowRoot,
  });

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  final FolderStorageService _folderService = GetIt.I<FolderStorageService>();
  final FolderNameIndex _index = GetIt.I<FolderNameIndex>();
  final RecentDestinationsService _recentsService =
      GetIt.I<RecentDestinationsService>();

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  List<Folder> _searchResults = const [];
  bool _isSearching = false;

  final List<_BreadcrumbEntry> _breadcrumbs = [];
  List<Folder>? _folders;
  bool _isLoading = true;

  // Resolved recent destinations, excluding any that are filtered out by
  // [excludeFolderIds] or no longer exist.
  List<_RecentEntry> _recentEntries = const [];

  String? get _currentParentId =>
      _breadcrumbs.isEmpty ? null : _breadcrumbs.last.id;

  @override
  void initState() {
    super.initState();
    // Pre-position the picker INSIDE the source item's current folder so
    // the user immediately sees siblings (the most common move target).
    // The previous behavior of always starting at root forced an extra
    // drill-down step for every move within a subtree.
    _initializeBreadcrumbsAndLoad();
    _resolveRecents();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _initializeBreadcrumbsAndLoad() async {
    final startId = widget.currentFolderId;
    if (startId.isEmpty) {
      // Source lives at root — keep breadcrumbs empty (start at root).
      await _loadFolders();
      return;
    }
    // Resolve ancestors + the current folder itself; if any link is
    // missing fall back to root rather than failing the whole picker.
    final ancestors = await _folderService.getAncestors(startId);
    final current = await _folderService.getFolderById(startId);
    if (!mounted) return;
    setState(() {
      _breadcrumbs
        ..clear()
        ..addAll(
          ancestors.map((f) => _BreadcrumbEntry(id: f.id, name: f.name)),
        );
      if (current != null) {
        _breadcrumbs.add(_BreadcrumbEntry(id: current.id, name: current.name));
      }
    });
    await _loadFolders();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final raw = _searchController.text.trim();
    _searchDebounce?.cancel();
    if (raw.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = const [];
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _runSearch(raw);
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searchQuery = query;
      _isSearching = true;
    });
    final results = await _index.search(
      query,
      excludeIds: widget.excludeFolderIds,
      limit: 50,
    );
    if (!mounted || _searchController.text.trim() != query) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    final allFolders = await _folderService.loadAllFoldersForParent(
      _currentParentId,
    );
    final folders = widget.excludeFolderIds.isEmpty
        ? allFolders
        : allFolders
              .where((f) => !widget.excludeFolderIds.contains(f.id))
              .toList();
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _isLoading = false;
    });
  }

  Future<void> _resolveRecents() async {
    final ids = _recentsService.recents;
    if (ids.isEmpty) {
      if (mounted) setState(() => _recentEntries = const []);
      return;
    }
    final entries = <_RecentEntry>[];
    for (final id in ids) {
      if (id == null) {
        if (widget.allowRoot) {
          entries.add(const _RecentEntry(id: null, name: null));
        }
        continue;
      }
      if (widget.excludeFolderIds.contains(id)) continue;
      final folder = await _folderService.getFolderById(id);
      if (folder != null) {
        entries.add(_RecentEntry(id: id, name: folder.name));
      }
    }
    if (!mounted) return;
    setState(() => _recentEntries = entries);
  }

  void _navigateInto(Folder folder) {
    setState(() {
      _breadcrumbs.add(_BreadcrumbEntry(id: folder.id, name: folder.name));
    });
    _loadFolders();
  }

  void _navigateUp() {
    if (_breadcrumbs.isEmpty) return;
    setState(() => _breadcrumbs.removeLast());
    _loadFolders();
  }

  void _navigateToBreadcrumb(int index) {
    setState(() {
      if (index < 0) {
        _breadcrumbs.clear();
      } else {
        _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
      }
    });
    _loadFolders();
  }

  bool get _canSelectCurrent {
    final currentId = _currentParentId ?? '';
    if (currentId == widget.currentFolderId) return false;
    if (currentId.isEmpty && !widget.allowRoot) return false;
    return true;
  }

  void _confirmSelection(String? id) {
    AppNavigator.pop(context, id ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final destinationName = _breadcrumbs.isEmpty
        ? l10n.rootFolder
        : _breadcrumbs.last.name;

    return AlertDialog(
      title: Text(l10n.moveToTitle),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchField(l10n, colorScheme),
            const SizedBox(height: 8),
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? _buildSearchResults(l10n, colorScheme)
                  : _buildBrowseView(l10n, colorScheme),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => AppNavigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.drive_file_move_outlined, size: 18),
          onPressed: _canSelectCurrent
              ? () => _confirmSelection(_currentParentId)
              : null,
          // Dynamic label — names the actual destination so the user
          // is never in doubt about WHERE the move will land. This is
          // the single biggest disambiguation in the redesign: even if
          // the address bar is somehow misread, the action button
          // restates the target by name.
          label: Text(l10n.moveToDestination(destinationName)),
        ),
      ],
    );
  }

  Widget _buildSearchField(AppLocalizations l10n, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.searchFolders,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged();
                  },
                  visualDensity: VisualDensity.compact,
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildSearchResults(AppLocalizations l10n, ColorScheme colorScheme) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.noFoldersFound,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final folder = _searchResults[index];
        return ListTile(
          leading: Icon(Icons.folder, color: AppColors.folderIcon(context)),
          title: Text(folder.name),
          dense: true,
          // Tapping the source's current parent is allowed; the move
          // coordinator surfaces an "already in this folder" snackbar
          // instead of greying the row out (which made the row look
          // un-navigable even though drill-in still worked).
          onTap: () => _confirmSelection(folder.id),
        );
      },
    );
  }

  Widget _buildBrowseView(AppLocalizations l10n, ColorScheme colorScheme) {
    final destinationName = _breadcrumbs.isEmpty
        ? l10n.rootFolder
        : _breadcrumbs.last.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_recentEntries.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              l10n.recentDestinations,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _recentEntries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final entry = _recentEntries[index];
                final label = entry.name ?? l10n.rootFolder;
                return ActionChip(
                  avatar: const Icon(Icons.history, size: 16),
                  label: Text(label),
                  onPressed: () => _confirmSelection(entry.id),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Address bar — modeled after a file-manager path control.
        // Visually separate from the list (outlined surface, padded,
        // labeled "Currently in:") so users never confuse it with a
        // tappable folder row. The full path with chevrons reads as
        // a navigation widget, not a content card.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _AddressBar(
            breadcrumbs: _breadcrumbs,
            rootLabel: l10n.rootFolder,
            currentlyInLabel: l10n.currentlyIn,
            backTooltip: l10n.back,
            onBack: _breadcrumbs.isEmpty ? null : _navigateUp,
            onTapRoot: () => _navigateToBreadcrumb(-1),
            onTapAncestor: _navigateToBreadcrumb,
          ),
        ),
        // Section label — tells the user that the rows below are
        // CHILDREN of the address-bar location. Without this overline
        // the list is ambiguous: are these siblings? children? all
        // folders? Naming the parent removes that ambiguity.
        _SectionLabel(text: l10n.subfoldersOf(destinationName)),
        const Divider(height: 1),
        Expanded(child: _buildFolderList(l10n, colorScheme)),
      ],
    );
  }

  Widget _buildFolderList(AppLocalizations l10n, ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final folders = _folders ?? [];
    if (folders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _breadcrumbs.isEmpty ? l10n.noFoldersAvailable : l10n.noSubfolders,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        // Single-action row, matching every modern file picker (Drive,
        // iOS Files, Finder, Notion): tapping a folder drills INTO it.
        // Selection is handled exclusively by the bottom "Move to <X>"
        // button, which always names the current location — so there's
        // no per-row selection control to clutter the list or compete
        // with the row tap.
        //
        // The trailing chevron is a PASSIVE affordance (not an
        // IconButton): it visually communicates "this row drills in"
        // without introducing a second hit target on the row.
        //
        // Note: we intentionally do NOT grey out the source item's current
        // parent folder. The MoveCoordinator surfaces an "already in this
        // folder" snackbar if the user confirms it from the bottom action,
        // and the user can still drill INTO the folder from here.
        return ListTile(
          leading: Icon(Icons.folder, color: AppColors.folderIcon(context)),
          title: Text(folder.name),
          trailing: Icon(
            Icons.chevron_right,
            size: 22,
            color: colorScheme.onSurfaceVariant,
          ),
          dense: true,
          onTap: () => _navigateInto(folder),
        );
      },
    );
  }
}

/// File-manager style address bar. Visually distinct from list rows
/// (outlined container, label prefix, path with chevrons) so users
/// read it as a navigation control rather than a pickable folder.
///
/// Pure presentational — owns no state, all interaction is delegated
/// to the parent through callbacks. Easy to test and to restyle.
class _AddressBar extends StatefulWidget {
  final List<_BreadcrumbEntry> breadcrumbs;
  final String rootLabel;
  final String currentlyInLabel;
  final String backTooltip;
  final VoidCallback? onBack;
  final VoidCallback onTapRoot;
  final ValueChanged<int> onTapAncestor;

  const _AddressBar({
    required this.breadcrumbs,
    required this.rootLabel,
    required this.currentlyInLabel,
    required this.backTooltip,
    required this.onBack,
    required this.onTapRoot,
    required this.onTapAncestor,
  });

  @override
  State<_AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<_AddressBar> {
  // Owns a scroll controller so we can keep the CURRENT segment visible
  // when the path overflows. Using a normal start-aligned scroll view
  // (no `reverse: true`) preserves the natural reading order: short
  // paths sit on the leading edge, long paths can be panned by the
  // user — but on every breadcrumb change we auto-jump to the end so
  // the user always sees where they are.
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _AddressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.breadcrumbs.length != widget.breadcrumbs.length ||
        (widget.breadcrumbs.isNotEmpty &&
            oldWidget.breadcrumbs.isNotEmpty &&
            oldWidget.breadcrumbs.last.id != widget.breadcrumbs.last.id)) {
      _scheduleScrollToEnd();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleScrollToEnd();
  }

  void _scheduleScrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top label — semantically tells the user "this row is your
            // CURRENT position, not a destination". Pairs a small folder
            // glyph with the label text so the address bar is identifiable
            // even with the path scrolled or truncated.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 12,
                    // Subtle, theme-driven tint — the icon is a quiet
                    // anchor, not a focal point. The bolded current
                    // segment in the path below carries the emphasis.
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.currentlyInLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            // Path row — back button + scrollable path crumbs.
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: widget.backTooltip,
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: _PathCrumbs(
                      breadcrumbs: widget.breadcrumbs,
                      rootLabel: widget.rootLabel,
                      onTapRoot: widget.onTapRoot,
                      onTapAncestor: widget.onTapAncestor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders `📁 Root › A › B › C` with each segment tappable. The path
/// opens with a subtle leading folder glyph as a visual anchor; the
/// last segment (the current folder) is bolded and uses primary color
/// so it reads as the focal point of the address bar.
class _PathCrumbs extends StatelessWidget {
  final List<_BreadcrumbEntry> breadcrumbs;
  final String rootLabel;
  final VoidCallback onTapRoot;
  final ValueChanged<int> onTapAncestor;

  const _PathCrumbs({
    required this.breadcrumbs,
    required this.rootLabel,
    required this.onTapRoot,
    required this.onTapAncestor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mutedStyle = textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final currentStyle = textTheme.bodyMedium?.copyWith(
      color: colorScheme.primary,
      fontWeight: FontWeight.w700,
    );

    final isAtRoot = breadcrumbs.isEmpty;
    final children = <Widget>[
      // Leading folder glyph — sized to the text x-height, tinted with
      // the muted theme color. Reads as part of the path, not a button.
      Padding(
        padding: const EdgeInsets.only(right: 6, left: 2),
        child: Icon(
          Icons.folder_outlined,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      _PathSegment(
        label: rootLabel,
        style: isAtRoot ? currentStyle : mutedStyle,
        onTap: isAtRoot ? null : onTapRoot,
      ),
    ];
    for (int i = 0; i < breadcrumbs.length; i++) {
      final isLast = i == breadcrumbs.length - 1;
      children
        ..add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              Icons.chevron_right,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        )
        ..add(
          _PathSegment(
            label: breadcrumbs[i].name,
            style: isLast ? currentStyle : mutedStyle,
            onTap: isLast ? null : () => onTapAncestor(i),
          ),
        );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _PathSegment extends StatelessWidget {
  final String label;
  final TextStyle? style;
  final VoidCallback? onTap;

  const _PathSegment({
    required this.label,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(label, style: style, maxLines: 1),
    );
    if (onTap == null) return text;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: text,
    );
  }
}

/// Section overline. Used to label the folder list as the CHILDREN of
/// the current address-bar location, e.g. "Subfolders of Folder C".
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _BreadcrumbEntry {
  final String id;
  final String name;

  const _BreadcrumbEntry({required this.id, required this.name});
}

class _RecentEntry {
  /// `null` means "root".
  final String? id;
  final String? name;

  const _RecentEntry({required this.id, required this.name});
}
