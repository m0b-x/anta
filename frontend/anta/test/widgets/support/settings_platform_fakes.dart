import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' show XFile;

/// The system file picker as the destructive settings paths meet it: it
/// hands back the path a test chose, or nothing — the user backing out.
///
/// Installed over [FilePickerPlatform.instance], the seam the plugin's own
/// static `FilePicker.pickFile` reads, so the pages run unchanged.
class FakeFilePicker extends FilePickerPlatform {
  /// What the next pick returns; `null` is a cancelled picker.
  String? nextPath;

  int picks = 0;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    picks++;
    final path = nextPath;
    return path == null ? null : _PickedFile(path);
  }

  /// Puts this picker in place for the current test and the plugin's own
  /// back afterwards.
  void install() {
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = this;
    addTearDown(() => FilePickerPlatform.instance = previous);
  }
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this._path);

  final String _path;

  @override
  String get name => p.basename(_path);

  @override
  Uri get uri => Uri.file(_path);

  @override
  XFile get xFile => XFile(_path);

  @override
  Future<int> length() => File(_path).length();

  @override
  Future<Uint8List> readAsBytes() => File(_path).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(_path).openRead().map(Uint8List.fromList);
}

/// Answers every call on [channel] with [answer] for the current test and
/// returns the list the calls are written into.
///
/// `SystemNavigator.pop` and the share sheet are the two ends of the
/// destructive paths that leave the app; a test proves they were reached by
/// reading the call, since neither has an effect a widget test could see.
List<MethodCall> recordMethodCalls(MethodChannel channel, {Object? answer}) {
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    return answer;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

/// Writes a file that passes `DatabaseManager.isSqliteFile` — the 16-byte
/// SQLite magic header and some padding — at [path]. The import paths copy
/// the file verbatim and never open it, so a header is all they read.
Future<File> writeSqliteHeaderFile(String path) async {
  final bytes = BytesBuilder()
    ..add('SQLite format 3\u0000'.codeUnits)
    ..add(Uint8List(84));
  final file = File(path);
  await file.parent.create(recursive: true);
  return file.writeAsBytes(bytes.takeBytes());
}
