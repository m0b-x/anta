import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/dev_options.dart';

/// Colors for different markdown block types
class MarkdownBlockColors {
  static const Color header1 = Color(0x30FF5722);
  static const Color header2 = Color(0x30FF9800);
  static const Color header3 = Color(0x30FFC107);
  static const Color header4 = Color(0x30FFEB3B);
  static const Color header5 = Color(0x30CDDC39);
  static const Color header6 = Color(0x308BC34A);
  static const Color codeBlock = Color(0x309E9E9E);
  static const Color inlineCode = Color(0x30607D8B);
  static const Color blockquote = Color(0x303F51B5);
  static const Color list = Color(0x302196F3);
  static const Color link = Color(0x3000BCD4);
  static const Color image = Color(0x30009688);
  static const Color table = Color(0x30795548);
  static const Color horizontalRule = Color(0x30E91E63);
  static const Color paragraph = Color(
    0x3000E5FF,
  ); // vibrant cyan for regular text

  /// Get a solid border color for a block type (used for boundary markers)
  static Color getBorderColorForType(String type) {
    switch (type.toLowerCase()) {
      case 'h1':
      case 'header1':
        return const Color(0xFFFF5722);
      case 'h2':
      case 'header2':
        return const Color(0xFFFF9800);
      case 'h3':
      case 'header3':
        return const Color(0xFFFFC107);
      case 'h4':
      case 'header4':
        return const Color(0xFFFFEB3B);
      case 'h5':
      case 'header5':
        return const Color(0xFFCDDC39);
      case 'h6':
      case 'header6':
        return const Color(0xFF8BC34A);
      case 'code':
      case 'codeblock':
      case 'fenced_code':
        return const Color(0xFF9E9E9E);
      case 'blockquote':
      case 'quote':
        return const Color(0xFF3F51B5);
      case 'list':
      case 'listitem':
        return const Color(0xFF2196F3);
      case 'link':
        return const Color(0xFF00BCD4);
      case 'image':
        return const Color(0xFF009688);
      case 'table':
        return const Color(0xFF795548);
      case 'hr':
        return const Color(0xFFE91E63);
      default:
        return const Color(0xFF00E5FF); // cyan for paragraph
    }
  }

  static Color getColorForType(String type) {
    switch (type.toLowerCase()) {
      case 'h1':
      case 'header1':
        return header1;
      case 'h2':
      case 'header2':
        return header2;
      case 'h3':
      case 'header3':
        return header3;
      case 'h4':
      case 'header4':
        return header4;
      case 'h5':
      case 'header5':
        return header5;
      case 'h6':
      case 'header6':
        return header6;
      case 'code':
      case 'codeblock':
      case 'fenced_code':
        return codeBlock;
      case 'inlinecode':
        return inlineCode;
      case 'blockquote':
      case 'quote':
        return blockquote;
      case 'list':
      case 'listitem':
      case 'ul':
      case 'ol':
        return list;
      case 'link':
      case 'a':
        return link;
      case 'image':
      case 'img':
        return image;
      case 'table':
        return table;
      case 'hr':
      case 'horizontalrule':
        return horizontalRule;
      default:
        return paragraph;
    }
  }
}

/// Wrapper widget that applies debug coloring to markdown blocks
class DebugBlockWrapper extends StatelessWidget {
  final Widget child;
  final String blockType;

  const DebugBlockWrapper({
    super.key,
    required this.child,
    required this.blockType,
  });

  @override
  Widget build(BuildContext context) {
    final devOptions = DevOptions.instance;

    if (!devOptions.colorMarkdownBlocks && !devOptions.showBlockBoundaries) {
      return child;
    }

    return Container(
      decoration: BoxDecoration(
        color: devOptions.colorMarkdownBlocks
            ? MarkdownBlockColors.getColorForType(blockType)
            : null,
        border: devOptions.showBlockBoundaries
            ? Border.all(
                color: MarkdownBlockColors.getColorForType(
                  blockType,
                ).withValues(alpha: 0.8),
                width: 1,
              )
            : null,
      ),
      child: child,
    );
  }
}

/// Overlay widget for showing cursor/selection info
class CursorInfoOverlay extends StatelessWidget {
  final int line;
  final int column;
  final int offset;
  final int? selectionStart;
  final int? selectionEnd;
  final int? selectionLength;

  const CursorInfoOverlay({
    super.key,
    required this.line,
    required this.column,
    required this.offset,
    this.selectionStart,
    this.selectionEnd,
    this.selectionLength,
  });

  @override
  Widget build(BuildContext context) {
    final devOptions = DevOptions.instance;
    final showCursor = devOptions.showCursorInfo;
    final showSelection = devOptions.showSelectionDetails;

    if (!showCursor && !showSelection) {
      return const SizedBox.shrink();
    }

    final hasSelection =
        selectionStart != null &&
        selectionEnd != null &&
        selectionStart != selectionEnd;

    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
            color: Colors.white,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showCursor) ...[
                Text('Ln $line, Col $column'),
                const SizedBox(width: 8),
                Text('Pos: $offset'),
              ],
              if (showSelection && hasSelection) ...[
                const SizedBox(width: 8),
                Container(width: 1, height: 12, color: Colors.white38),
                const SizedBox(width: 8),
                Text('Sel: $selectionStart-$selectionEnd'),
                const SizedBox(width: 4),
                Text('(${selectionLength ?? 0} chars)'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlay widget for showing render time
class RenderTimeOverlay extends StatelessWidget {
  final Duration renderTime;

  const RenderTimeOverlay({super.key, required this.renderTime});

  @override
  Widget build(BuildContext context) {
    if (!DevOptions.instance.showRenderTime) {
      return const SizedBox.shrink();
    }

    final ms = renderTime.inMicroseconds / 1000;
    final color = ms < 16
        ? Colors.green
        : (ms < 33 ? Colors.orange : Colors.red);

    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${ms.toStringAsFixed(2)} ms',
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Overlay widget for showing note size
class NoteSizeOverlay extends StatelessWidget {
  final int sizeInBytes;

  const NoteSizeOverlay({super.key, required this.sizeInBytes});

  @override
  Widget build(BuildContext context) {
    if (!DevOptions.instance.showNoteSize) {
      return const SizedBox.shrink();
    }

    String formatted;
    if (sizeInBytes < 1024) {
      formatted = '$sizeInBytes B';
    } else if (sizeInBytes < 1024 * 1024) {
      formatted = '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      formatted = '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Size: $formatted',
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Overlay for showing chunk loading status
class ChunkIndicatorOverlay extends StatelessWidget {
  final int currentChunk;
  final int totalChunks;
  final List<int> loadedChunks;

  const ChunkIndicatorOverlay({
    super.key,
    required this.currentChunk,
    required this.totalChunks,
    required this.loadedChunks,
  });

  @override
  Widget build(BuildContext context) {
    if (!DevOptions.instance.showChunkIndicators) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Chunks: ${loadedChunks.length}/$totalChunks',
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 100,
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: List.generate(totalChunks, (i) {
                  final isLoaded = loadedChunks.contains(i);
                  final isCurrent = i == currentChunk;
                  return Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Colors.blue
                          : (isLoaded ? Colors.green : Colors.grey),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget to visualize whitespace characters in text
class WhitespaceVisualizer extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const WhitespaceVisualizer({super.key, required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    if (!DevOptions.instance.showWhitespace) {
      return Text(text, style: style);
    }

    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == ' ' || char == '\t' || char == '\n') {
        // Flush buffer
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(text: buffer.toString(), style: style));
          buffer.clear();
        }
        // Add whitespace indicator
        String indicator;
        Color color;
        if (char == ' ') {
          indicator = '·';
          color = Colors.grey;
        } else if (char == '\t') {
          indicator = '→';
          color = Colors.orange;
        } else {
          indicator = '↵\n';
          color = Colors.blue;
        }
        spans.add(
          TextSpan(
            text: indicator,
            style:
                style?.copyWith(color: color) ??
                TextStyle(color: color, fontSize: 12),
          ),
        );
      } else {
        buffer.write(char);
      }
    }

    // Flush remaining buffer
    if (buffer.isNotEmpty) {
      spans.add(TextSpan(text: buffer.toString(), style: style));
    }

    return Text.rich(TextSpan(children: spans));
  }
}

/// FPS counter overlay using a simple frame timing approach
class FpsCounterOverlay extends StatefulWidget {
  const FpsCounterOverlay({super.key});

  @override
  State<FpsCounterOverlay> createState() => _FpsCounterOverlayState();
}

class _FpsCounterOverlayState extends State<FpsCounterOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<int> _frameTimes = [];
  int _fps = 0;
  int _lastTime = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds;
    if (_lastTime > 0) {
      _frameTimes.add(now - _lastTime);
      if (_frameTimes.length > 60) {
        _frameTimes.removeAt(0);
      }
      if (_frameTimes.length >= 10) {
        final avg = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
        final newFps = (1000000 / avg).round();
        if (newFps != _fps) {
          setState(() => _fps = newFps);
        }
      }
    }
    _lastTime = now;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DevOptions.instance.showFpsCounter) {
      return const SizedBox.shrink();
    }

    final color = _fps >= 55
        ? Colors.green
        : (_fps >= 30 ? Colors.orange : Colors.red);

    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '$_fps FPS',
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Composite overlay that shows all enabled debug info
class DebugOverlayStack extends StatelessWidget {
  final Widget child;
  final int? cursorLine;
  final int? cursorColumn;
  final int? cursorOffset;
  final int? selectionStart;
  final int? selectionEnd;
  final int? noteSize;
  final Duration? renderTime;
  final int? currentChunk;
  final int? totalChunks;
  final List<int>? loadedChunks;

  const DebugOverlayStack({
    super.key,
    required this.child,
    this.cursorLine,
    this.cursorColumn,
    this.cursorOffset,
    this.selectionStart,
    this.selectionEnd,
    this.noteSize,
    this.renderTime,
    this.currentChunk,
    this.totalChunks,
    this.loadedChunks,
  });

  @override
  Widget build(BuildContext context) {
    final devOptions = DevOptions.instance;

    // Early return if nothing enabled
    if (!devOptions.anyEnabled) {
      return child;
    }

    return ListenableBuilder(
      listenable: devOptions,
      builder: (context, _) {
        return Stack(
          children: [
            child,
            if (cursorLine != null &&
                cursorColumn != null &&
                cursorOffset != null)
              CursorInfoOverlay(
                line: cursorLine!,
                column: cursorColumn!,
                offset: cursorOffset!,
                selectionStart: selectionStart,
                selectionEnd: selectionEnd,
                selectionLength: selectionStart != null && selectionEnd != null
                    ? (selectionEnd! - selectionStart!).abs()
                    : null,
              ),
            if (noteSize != null) NoteSizeOverlay(sizeInBytes: noteSize!),
            if (renderTime != null) RenderTimeOverlay(renderTime: renderTime!),
            if (currentChunk != null &&
                totalChunks != null &&
                loadedChunks != null)
              ChunkIndicatorOverlay(
                currentChunk: currentChunk!,
                totalChunks: totalChunks!,
                loadedChunks: loadedChunks!,
              ),
            if (devOptions.showFpsCounter) const FpsCounterOverlay(),
          ],
        );
      },
    );
  }
}
