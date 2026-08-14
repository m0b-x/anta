import '../interfaces/markdown_shortcut_handler.dart';
import '../handlers/header_shortcut_handler.dart';
import '../handlers/date_shortcut_handler.dart';
import '../handlers/default_shortcut_handler.dart';
import '../handlers/counter_shortcut_handler.dart';

class ShortcutHandlerFactory {
  static final CounterShortcutHandler _counterHandler =
      CounterShortcutHandler();

  static final Map<String, MarkdownShortcutHandler> _handlers = {
    'header': HeaderShortcutHandler(),
    'date': DateShortcutHandler(),
    'counter': _counterHandler,
    'default': DefaultShortcutHandler(),
  };

  static MarkdownShortcutHandler getHandler(String insertType) {
    return _handlers[insertType] ?? _handlers['default']!;
  }

  static CounterShortcutHandler get counterHandler => _counterHandler;
}
