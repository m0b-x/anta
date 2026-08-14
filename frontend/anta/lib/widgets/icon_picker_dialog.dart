import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../config/available_icons.dart';
import '../services/app_navigator.dart';

class _IconSearchIndex {
  static _IconSearchIndex? _instance;
  static _IconSearchIndex get instance => _instance ??= _IconSearchIndex._();

  late final Map<String, Set<IconData>> _keywordToIcons;
  late final List<String> _sortedKeywords;

  _IconSearchIndex._() {
    _keywordToIcons = {};

    final iconKeywords = <IconData, List<String>>{
      Icons.tag: ['tag', 'label', 'hash'],
      Icons.star: ['star', 'favorite', 'rating', 'important'],
      Icons.star_outline: ['star', 'outline', 'rating'],
      Icons.favorite: ['favorite', 'heart', 'love', 'like'],
      Icons.favorite_border: ['favorite', 'heart', 'outline'],
      Icons.bookmark: ['bookmark', 'save', 'mark'],
      Icons.bookmark_border: ['bookmark', 'outline'],
      Icons.flag: ['flag', 'report', 'mark', 'important'],
      Icons.push_pin: ['pin', 'push', 'attach', 'stick'],
      Icons.label: ['label', 'tag', 'category'],
      Icons.local_offer: ['offer', 'tag', 'price', 'sale'],
      Icons.lightbulb: ['lightbulb', 'idea', 'tip', 'hint', 'bright'],
      Icons.lightbulb_outline: ['lightbulb', 'idea', 'outline'],
      Icons.warning: ['warning', 'alert', 'caution', 'danger'],
      Icons.warning_amber: ['warning', 'amber', 'caution'],
      Icons.info: ['info', 'information', 'about', 'details'],
      Icons.info_outline: ['info', 'outline', 'information'],
      Icons.error: ['error', 'mistake', 'wrong', 'problem'],
      Icons.error_outline: ['error', 'outline'],
      Icons.check_circle: ['check', 'done', 'complete', 'success', 'yes'],
      Icons.check_circle_outline: ['check', 'done', 'outline'],
      Icons.cancel: ['cancel', 'close', 'remove', 'no'],
      Icons.help: ['help', 'question', 'support', 'faq'],
      Icons.help_outline: ['help', 'question', 'outline'],
      Icons.note: ['note', 'memo', 'write', 'text'],
      Icons.note_add: ['note', 'add', 'new', 'create'],
      Icons.description: ['description', 'document', 'file', 'text'],
      Icons.article: ['article', 'blog', 'post', 'read'],
      Icons.menu_book: ['book', 'menu', 'read', 'library'],
      Icons.auto_stories: ['stories', 'book', 'read', 'pages'],
      Icons.sticky_note_2: ['sticky', 'note', 'memo', 'postit'],
      Icons.text_snippet: ['text', 'snippet', 'code', 'content'],
      Icons.subject: ['subject', 'text', 'content', 'lines'],
      Icons.short_text: ['short', 'text', 'brief'],
      Icons.notes: ['notes', 'lines', 'text'],
      Icons.format_bold: ['bold', 'strong', 'format', 'text'],
      Icons.format_italic: ['italic', 'slant', 'format', 'text'],
      Icons.format_underlined: ['underline', 'format', 'text'],
      Icons.strikethrough_s: ['strikethrough', 'cross', 'delete', 'format'],
      Icons.format_quote: ['quote', 'citation', 'blockquote'],
      Icons.format_list_bulleted: ['bullet', 'list', 'unordered'],
      Icons.format_list_numbered: ['numbered', 'list', 'ordered'],
      Icons.code: ['code', 'programming', 'developer', 'syntax'],
      Icons.data_object: ['data', 'object', 'json', 'code'],
      Icons.terminal: ['terminal', 'command', 'shell', 'console'],
      Icons.highlight: ['highlight', 'marker', 'emphasis'],
      Icons.format_color_text: ['color', 'text', 'format'],
      Icons.text_format: ['text', 'format', 'style'],
      Icons.today: ['today', 'date', 'calendar', 'day'],
      Icons.event: ['event', 'calendar', 'schedule', 'appointment'],
      Icons.calendar_today: ['calendar', 'today', 'date'],
      Icons.schedule: ['schedule', 'time', 'clock', 'plan'],
      Icons.access_time: ['time', 'clock', 'hour'],
      Icons.timer: ['timer', 'stopwatch', 'countdown'],
      Icons.alarm: ['alarm', 'clock', 'alert', 'reminder'],
      Icons.history: ['history', 'past', 'recent', 'undo'],
      Icons.check_box: ['checkbox', 'check', 'done', 'task'],
      Icons.check_box_outline_blank: ['checkbox', 'empty', 'unchecked'],
      Icons.radio_button_checked: ['radio', 'checked', 'selected'],
      Icons.radio_button_unchecked: ['radio', 'unchecked', 'empty'],
      Icons.task_alt: ['task', 'done', 'complete', 'check'],
      Icons.assignment: ['assignment', 'task', 'clipboard', 'work'],
      Icons.assignment_turned_in: ['assignment', 'done', 'complete'],
      Icons.pending_actions: ['pending', 'actions', 'waiting'],
      Icons.rule: ['rule', 'check', 'validate'],
      Icons.fitness_center: [
        'fitness',
        'gym',
        'workout',
        'exercise',
        'weight',
        'dumbbell',
      ],
      Icons.sports_gymnastics: ['gymnastics', 'sports', 'exercise', 'stretch'],
      Icons.self_improvement: ['self', 'improvement', 'meditation', 'yoga'],
      Icons.monitor_weight: ['weight', 'scale', 'measure', 'body'],
      Icons.accessibility_new: ['accessibility', 'person', 'body', 'stretch'],
      Icons.directions_run: ['run', 'running', 'jog', 'cardio', 'exercise'],
      Icons.directions_walk: ['walk', 'walking', 'steps', 'exercise'],
      Icons.sports: ['sports', 'ball', 'game', 'play'],
      Icons.emoji_events: ['trophy', 'award', 'winner', 'achievement', 'prize'],
      Icons.military_tech: ['medal', 'military', 'badge', 'achievement'],
      Icons.folder: ['folder', 'directory', 'organize'],
      Icons.folder_open: ['folder', 'open', 'directory'],
      Icons.category: ['category', 'organize', 'group', 'type'],
      Icons.inventory_2: ['inventory', 'box', 'package', 'storage'],
      Icons.dashboard: ['dashboard', 'overview', 'panel'],
      Icons.grid_view: ['grid', 'view', 'tiles', 'layout'],
      Icons.view_list: ['list', 'view', 'rows', 'layout'],
      Icons.sort: ['sort', 'order', 'arrange'],
      Icons.filter_list: ['filter', 'list', 'refine'],
      Icons.chat: ['chat', 'message', 'talk', 'conversation'],
      Icons.chat_bubble: ['chat', 'bubble', 'message'],
      Icons.comment: ['comment', 'feedback', 'reply'],
      Icons.message: ['message', 'text', 'sms', 'chat'],
      Icons.forum: ['forum', 'discussion', 'community'],
      Icons.question_answer: ['question', 'answer', 'faq', 'qa'],
      Icons.image: ['image', 'photo', 'picture', 'gallery'],
      Icons.photo_camera: ['camera', 'photo', 'picture', 'capture'],
      Icons.videocam: ['video', 'camera', 'record', 'movie'],
      Icons.music_note: ['music', 'note', 'song', 'audio'],
      Icons.audiotrack: ['audio', 'track', 'music', 'sound'],
      Icons.mic: ['mic', 'microphone', 'voice', 'record'],
      Icons.attachment: ['attachment', 'attach', 'file', 'clip'],
      Icons.edit: ['edit', 'pencil', 'modify', 'change'],
      Icons.delete: ['delete', 'trash', 'remove', 'bin'],
      Icons.save: ['save', 'disk', 'store'],
      Icons.share: ['share', 'send', 'social'],
      Icons.send: ['send', 'submit', 'arrow'],
      Icons.download: ['download', 'save', 'get'],
      Icons.upload: ['upload', 'send', 'cloud'],
      Icons.link: ['link', 'url', 'chain', 'connect'],
      Icons.link_off: ['link', 'off', 'unlink', 'disconnect'],
      Icons.add_link: ['add', 'link', 'url', 'connect'],
      Icons.content_copy: ['copy', 'duplicate', 'clipboard'],
      Icons.content_paste: ['paste', 'clipboard', 'insert'],
      Icons.arrow_upward: ['arrow', 'up', 'upward', 'increase'],
      Icons.arrow_downward: ['arrow', 'down', 'downward', 'decrease'],
      Icons.arrow_forward: ['arrow', 'forward', 'right', 'next'],
      Icons.arrow_back: ['arrow', 'back', 'left', 'previous'],
      Icons.trending_up: ['trending', 'up', 'increase', 'growth', 'progress'],
      Icons.trending_down: ['trending', 'down', 'decrease', 'decline'],
      Icons.trending_flat: ['trending', 'flat', 'stable', 'neutral'],
      Icons.north_east: ['north', 'east', 'diagonal', 'arrow'],
      Icons.south_west: ['south', 'west', 'diagonal', 'arrow'],
      Icons.priority_high: [
        'priority',
        'high',
        'important',
        'urgent',
        'exclamation',
      ],
      Icons.new_releases: ['new', 'releases', 'badge', 'announcement'],
      Icons.bolt: ['bolt', 'lightning', 'power', 'energy', 'fast'],
      Icons.flash_on: ['flash', 'lightning', 'quick', 'fast'],
      Icons.verified: ['verified', 'check', 'approved', 'authentic'],
      Icons.workspace_premium: ['premium', 'crown', 'vip', 'special'],
      Icons.diamond: ['diamond', 'gem', 'precious', 'valuable'],
      Icons.eco: ['eco', 'leaf', 'nature', 'green', 'environment'],
      Icons.park: ['park', 'tree', 'nature', 'forest'],
      Icons.pets: ['pets', 'paw', 'animal', 'dog', 'cat'],
      Icons.psychology: ['psychology', 'brain', 'mind', 'think'],
      Icons.rocket_launch: ['rocket', 'launch', 'startup', 'fast', 'space'],
      Icons.science: ['science', 'lab', 'experiment', 'flask'],
      Icons.biotech: ['biotech', 'dna', 'biology', 'genetics'],
      Icons.wb_sunny: ['sunny', 'sun', 'weather', 'day', 'bright'],
      Icons.nightlight: ['night', 'moon', 'dark', 'sleep'],
      Icons.cloud: ['cloud', 'weather', 'sky', 'storage'],
      Icons.water_drop: ['water', 'drop', 'rain', 'liquid'],
      Icons.ac_unit: ['ac', 'snow', 'cold', 'winter', 'freeze'],
      Icons.local_fire_department: ['fire', 'flame', 'hot', 'burn'],
      Icons.person: ['person', 'user', 'profile', 'account'],
      Icons.people: ['people', 'users', 'group', 'team'],
      Icons.groups: ['groups', 'team', 'people', 'community'],
      Icons.face: ['face', 'emoji', 'person', 'avatar'],
      Icons.emoji_emotions: ['emoji', 'emotions', 'happy', 'smile'],
      Icons.sentiment_satisfied: ['sentiment', 'satisfied', 'happy', 'smile'],
      Icons.sentiment_dissatisfied: [
        'sentiment',
        'dissatisfied',
        'sad',
        'unhappy',
      ],
      Icons.thumb_up: ['thumb', 'up', 'like', 'approve', 'good'],
      Icons.thumb_down: ['thumb', 'down', 'dislike', 'disapprove', 'bad'],
      Icons.style: ['style', 'design', 'fashion'],
      Icons.palette: ['palette', 'color', 'art', 'paint'],
      Icons.brush: ['brush', 'paint', 'art', 'draw'],
      Icons.color_lens: ['color', 'lens', 'palette', 'theme'],
      Icons.auto_awesome: ['awesome', 'sparkle', 'magic', 'star'],
      Icons.grade: ['grade', 'star', 'rating', 'score'],
      Icons.toll: ['toll', 'coins', 'money', 'payment'],
      Icons.lens: ['lens', 'circle', 'dot', 'point'],
      Icons.circle: ['circle', 'dot', 'bullet', 'round'],
      Icons.square: ['square', 'box', 'shape'],
      Icons.change_history: ['triangle', 'change', 'history', 'shape'],
      Icons.hexagon: ['hexagon', 'shape', 'polygon'],
      Icons.computer: ['computer', 'pc'],
    };

    for (final entry in iconKeywords.entries) {
      for (final keyword in entry.value) {
        (_keywordToIcons[keyword] ??= {}).add(entry.key);
      }
    }

    _sortedKeywords = _keywordToIcons.keys.toList()..sort();
  }

  Set<IconData> search(String query) {
    if (query.isEmpty) return {};

    final results = <IconData>{};

    for (final keyword in _sortedKeywords) {
      if (keyword.startsWith(query)) {
        results.addAll(_keywordToIcons[keyword]!);
      }
    }

    return results;
  }
}

class IconPickerDialog extends StatefulWidget {
  final IconData? currentIcon;

  const IconPickerDialog({super.key, this.currentIcon});

  @override
  State<IconPickerDialog> createState() => _IconPickerDialogState();
}

class _IconPickerDialogState extends State<IconPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final _searchIndex = _IconSearchIndex.instance;
  List<IconData> _filteredIcons = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredIcons = List.from(AvailableIcons.all);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query == _searchQuery) return;

    _searchQuery = query;
    setState(() {
      if (query.isEmpty) {
        _filteredIcons = List.from(AvailableIcons.all);
      } else {
        final matchedIcons = _searchIndex.search(query);
        _filteredIcons = AvailableIcons.all
            .where((icon) => matchedIcons.contains(icon))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.selectIcon),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchIcons,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredIcons.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.noIconsFound,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: _filteredIcons.length,
                      itemBuilder: (context, index) {
                        final icon = _filteredIcons[index];
                        final isSelected = widget.currentIcon == icon;
                        return InkWell(
                          onTap: () => AppNavigator.pop(context, icon),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : null,
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface
                                          .withValues(alpha: 0.2),
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              icon,
                              size: 28,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => AppNavigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
