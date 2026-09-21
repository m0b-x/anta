import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/src/signing.dart';

const String _complete = 'storePassword=pw\n'
    'keyPassword=pw\n'
    'keyAlias=anta\n'
    'storeFile=release-keystore.jks\n';

void main() {
  group('parseKeyProperties', () {
    test('reads key=value pairs, trimming and skipping comments', () {
      final map = parseKeyProperties(
        '# signing\r\n! also a comment\r\n keyAlias = anta \r\n'
        'storeFile=release-keystore.jks\r\n\r\n',
      );
      expect(map, {'keyAlias': 'anta', 'storeFile': 'release-keystore.jks'});
    });

    test('accepts the colon separator and keeps later separators', () {
      expect(
        parseKeyProperties(r'storeFile: C:\keys\anta.jks'),
        {'storeFile': r'C:\keys\anta.jks'},
      );
    });
  });

  group('resolveKeystorePath', () {
    test('a relative storeFile lives in the app module, like Gradle file()', () {
      expect(
        resolveKeystorePath('release-keystore.jks', appModuleDir: 'app'),
        'app${Platform.pathSeparator}release-keystore.jks',
      );
    });

    test('an absolute storeFile is kept', () {
      final absolute =
          Platform.isWindows ? r'C:\keys\anta.jks' : '/keys/anta.jks';
      expect(resolveKeystorePath(absolute, appModuleDir: 'app'), absolute);
    });
  });

  group('signingStatus', () {
    test('no key.properties means the debug key, spelled out', () {
      final status = signingStatus(
        propertiesText: null,
        appModuleDir: 'app',
        exists: (_) => true,
      );
      expect(status.state, SigningState.noProperties);
      expect(status.ready, isFalse);
      expect(status.describe(), contains('debug key'));
    });

    test('names the keys a partial file lacks', () {
      final status = signingStatus(
        propertiesText: 'storeFile=k.jks\nkeyAlias=a\n',
        appModuleDir: 'app',
        exists: (_) => true,
      );
      expect(status.state, SigningState.incompleteProperties);
      expect(status.missingKeys, ['storePassword', 'keyPassword']);
      expect(status.describe(), contains('storePassword, keyPassword'));
    });

    test('a properties file without its keystore is not ready either', () {
      final status = signingStatus(
        propertiesText: _complete,
        appModuleDir: 'app',
        exists: (_) => false,
      );
      expect(status.state, SigningState.keystoreMissing);
      expect(status.keystorePath, endsWith('release-keystore.jks'));
      expect(status.describe(), contains('does not exist'));
    });

    test('both files present is ready and reports the alias', () {
      final status = signingStatus(
        propertiesText: _complete,
        appModuleDir: 'app',
        exists: (_) => true,
      );
      expect(status.ready, isTrue);
      expect(status.keyAlias, 'anta');
      expect(status.describe(), contains('alias anta'));
    });
  });

  test('readSigningStatus reads the checkout layout', () {
    final root = Directory.systemTemp.createTempSync('anta_signing');
    addTearDown(() => root.deleteSync(recursive: true));
    expect(readSigningStatus(root.path).state, SigningState.noProperties);
    Directory('${root.path}/android/app').createSync(recursive: true);
    File('${root.path}/android/key.properties').writeAsStringSync(_complete);
    expect(readSigningStatus(root.path).state, SigningState.keystoreMissing);
    File('${root.path}/android/app/release-keystore.jks').writeAsBytesSync([0]);
    expect(readSigningStatus(root.path).ready, isTrue);
  });

  test('missingFirebaseFiles lists the gitignored files a build needs', () {
    expect(missingFirebaseFiles('root', exists: (_) => true), isEmpty);
    expect(
      missingFirebaseFiles(
        'root',
        exists: (path) => path.endsWith('firebase_options.dart'),
      ),
      ['android/app/google-services.json'],
    );
  });

  test('the remedy names both files and the data-loss trap', () {
    expect(signingRemedy, contains(keyPropertiesRelative));
    expect(signingRemedy, contains(defaultKeystoreRelative));
    expect(signingRemedy, contains('wipe'));
  });
}
