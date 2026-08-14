import 'package:flutter/material.dart';
import '../config/available_icons.dart';

/// Utility class for icon handling that supports tree-shaking.
///
/// Flutter's tree-shaking cannot work with dynamic IconData creation
/// (e.g., `IconData(codePoint, fontFamily: 'MaterialIcons')`).
/// This class provides a mapping from code points to constant icon references,
/// allowing Flutter to tree-shake unused icons while still supporting
/// stored icon code points in the database.
class IconUtils {
  IconUtils._();

  static Map<int, IconData>? _cachedIconMap;

  static Map<int, IconData> get _iconMap {
    _cachedIconMap ??= _buildIconMap();
    return _cachedIconMap!;
  }

  static Map<int, IconData> _buildIconMap() {
    final map = <int, IconData>{
      // Format icons
      Icons.format_bold.codePoint: Icons.format_bold,
      Icons.format_italic.codePoint: Icons.format_italic,
      Icons.strikethrough_s.codePoint: Icons.strikethrough_s,
      Icons.title.codePoint: Icons.title,

      // List icons
      Icons.circle.codePoint: Icons.circle,
      Icons.fiber_manual_record.codePoint: Icons.fiber_manual_record,
      Icons.format_list_bulleted.codePoint: Icons.format_list_bulleted,
      Icons.format_list_numbered.codePoint: Icons.format_list_numbered,

      // Text icons
      Icons.tag.codePoint: Icons.tag,
      Icons.check_box_outline_blank.codePoint: Icons.check_box_outline_blank,
      Icons.check_box.codePoint: Icons.check_box,
      Icons.format_quote.codePoint: Icons.format_quote,

      // Other icons
      Icons.link.codePoint: Icons.link,
      Icons.today.codePoint: Icons.today,
      Icons.code.codePoint: Icons.code,
      Icons.integration_instructions.codePoint: Icons.integration_instructions,
      Icons.table_chart.codePoint: Icons.table_chart,
      Icons.horizontal_rule.codePoint: Icons.horizontal_rule,

      // Common picker icons
      Icons.email.codePoint: Icons.email,
      Icons.phone.codePoint: Icons.phone,
      Icons.location_on.codePoint: Icons.location_on,
      Icons.schedule.codePoint: Icons.schedule,
      Icons.person.codePoint: Icons.person,
      Icons.settings.codePoint: Icons.settings,
      Icons.home.codePoint: Icons.home,
      Icons.image.codePoint: Icons.image,
      Icons.music_note.codePoint: Icons.music_note,
      Icons.videocam.codePoint: Icons.videocam,
      Icons.edit.codePoint: Icons.edit,
      Icons.delete.codePoint: Icons.delete,
      Icons.close.codePoint: Icons.close,
      Icons.check.codePoint: Icons.check,
      Icons.add.codePoint: Icons.add,
      Icons.remove.codePoint: Icons.remove,
      Icons.search.codePoint: Icons.search,
      Icons.menu.codePoint: Icons.menu,
      Icons.arrow_back.codePoint: Icons.arrow_back,
      Icons.arrow_forward.codePoint: Icons.arrow_forward,
      Icons.arrow_upward.codePoint: Icons.arrow_upward,
      Icons.arrow_downward.codePoint: Icons.arrow_downward,
      Icons.refresh.codePoint: Icons.refresh,
      Icons.save.codePoint: Icons.save,
      Icons.share.codePoint: Icons.share,
      Icons.content_copy.codePoint: Icons.content_copy,
      Icons.content_cut.codePoint: Icons.content_cut,
      Icons.help.codePoint: Icons.help,
      Icons.expand_more.codePoint: Icons.expand_more,
      Icons.expand_less.codePoint: Icons.expand_less,
      Icons.visibility.codePoint: Icons.visibility,
      Icons.visibility_off.codePoint: Icons.visibility_off,
      Icons.lock.codePoint: Icons.lock,
      Icons.lock_open.codePoint: Icons.lock_open,
      Icons.chat.codePoint: Icons.chat,
      Icons.comment.codePoint: Icons.comment,
      Icons.folder.codePoint: Icons.folder,
      Icons.insert_drive_file.codePoint: Icons.insert_drive_file,
      Icons.cloud.codePoint: Icons.cloud,
      Icons.cloud_download.codePoint: Icons.cloud_download,
      Icons.cloud_upload.codePoint: Icons.cloud_upload,
      Icons.download.codePoint: Icons.download,
      Icons.upload.codePoint: Icons.upload,
      Icons.camera_alt.codePoint: Icons.camera_alt,
      Icons.photo.codePoint: Icons.photo,
      Icons.play_arrow.codePoint: Icons.play_arrow,
      Icons.pause.codePoint: Icons.pause,
      Icons.stop.codePoint: Icons.stop,
      Icons.fast_forward.codePoint: Icons.fast_forward,
      Icons.fast_rewind.codePoint: Icons.fast_rewind,
      Icons.skip_next.codePoint: Icons.skip_next,
      Icons.skip_previous.codePoint: Icons.skip_previous,
      Icons.volume_up.codePoint: Icons.volume_up,
      Icons.volume_off.codePoint: Icons.volume_off,
      Icons.brightness_high.codePoint: Icons.brightness_high,
      Icons.brightness_low.codePoint: Icons.brightness_low,
      Icons.wifi.codePoint: Icons.wifi,
      Icons.bluetooth.codePoint: Icons.bluetooth,
      Icons.battery_full.codePoint: Icons.battery_full,
      Icons.signal_cellular_4_bar.codePoint: Icons.signal_cellular_4_bar,
      Icons.dark_mode.codePoint: Icons.dark_mode,
      Icons.light_mode.codePoint: Icons.light_mode,
      Icons.error.codePoint: Icons.error,
    };

    for (final icon in AvailableIcons.all) {
      map[icon.codePoint] = icon;
    }

    return map;
  }

  /// Gets an IconData from a code point.
  /// If the code point is not in the map, returns a fallback icon.
  static IconData getIcon(int codePoint, {IconData fallback = Icons.tag}) {
    return _iconMap[codePoint] ?? fallback;
  }

  /// Gets an IconData from code point and font family.
  /// This is the replacement for dynamic IconData creation.
  /// Only MaterialIcons are supported for tree-shaking.
  static IconData getIconFromData(int codePoint, String fontFamily) {
    // All icons should be MaterialIcons and in the map
    // Return fallback for any unsupported icon to maintain tree-shaking
    return getIcon(codePoint);
  }

  /// Checks if an icon code point is in the supported map.
  static bool isSupported(int codePoint) {
    return _iconMap.containsKey(codePoint);
  }

  /// Gets all supported icons as a list for icon pickers.
  static List<IconData> get supportedIcons => _iconMap.values.toList();

  /// Gets all supported icon code points.
  static List<int> get supportedCodePoints => _iconMap.keys.toList();
}
