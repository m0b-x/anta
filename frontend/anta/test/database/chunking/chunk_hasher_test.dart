import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/chunking/chunk_hasher.dart';

/// The chunk hash is a stored identity — and the chunked wire's document id
/// (`docs/scalability-roadmap.md` §5.2 S4) — so it is pinned to known
/// answers: SHA-256 over the UTF-16 code units, little-endian, in lowercase
/// hex. The vectors come from .NET's SHA-256 over `Encoding.Unicode` bytes,
/// an implementation independent of `package:crypto`.
void main() {
  test('the empty text hashes as SHA-256 of no bytes', () {
    expect(
      ChunkHasher.hash(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('ASCII hashes over its UTF-16LE bytes', () {
    expect(
      ChunkHasher.hash('abc'),
      '13e228567e8249fce53337f25d7970de3bd68ab2653424c7b8f9fd05e33caedf',
    );
  });

  test('a diacritic and a surrogate pair hash over their code units', () {
    expect(
      ChunkHasher.hash('Squat ș \u{1F3CB}'),
      'b91fd57f4f94509c5735d6039b3dbae61a3c68240bb396b7508b88025e9b337b',
    );
  });

  test('a range hashes as its substring', () {
    const text = '-- abc --';
    expect(ChunkHasher.hash(text, 3, 6), ChunkHasher.hash('abc'));
  });

  test('two lone surrogates never hash alike', () {
    expect(ChunkHasher.hash('\uD83C'), isNot(ChunkHasher.hash('\uD83D')));
  });
}
