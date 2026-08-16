import 'package:equatable/equatable.dart';

/// The signed-in cloud account, decoupled from `firebase_auth`'s `User` so
/// Firebase types stay out of the bloc and UI layers.
class AppUser extends Equatable {
  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  const AppUser({
    required this.uid,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  @override
  List<Object?> get props => [uid, displayName, email, photoUrl];
}
