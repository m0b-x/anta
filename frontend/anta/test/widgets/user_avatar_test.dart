import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/app_user.dart';
import 'package:anta/widgets/user_avatar.dart';

Widget _wrap(AppUser user) => MaterialApp(
  home: Scaffold(body: UserAvatar(user: user)),
);

void main() {
  testWidgets('falls back to the person icon without a photo', (tester) async {
    await tester.pumpWidget(_wrap(const AppUser(uid: 'u1')));

    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.foregroundImage, isNull);
    // Must stay null alongside a null image, or CircleAvatar asserts.
    expect(avatar.onForegroundImageError, isNull);
  });

  testWidgets('uses the photo when one is present', (tester) async {
    await tester.pumpWidget(
      _wrap(const AppUser(uid: 'u1', photoUrl: 'https://example.com/a.png')),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.foregroundImage, isNotNull);
    expect(avatar.onForegroundImageError, isNotNull);
  });

  testWidgets('a failed photo fetch does not throw', (tester) async {
    await tester.pumpWidget(
      _wrap(const AppUser(uid: 'u1', photoUrl: 'https://example.com/a.png')),
    );
    // The test HTTP client fails the request; the error handler must swallow
    // it and leave the icon showing.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });
}
