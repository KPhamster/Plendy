class UserProfile {
  final String id;
  final String? username;
  final String? photoURL;

  UserProfile({
    required this.id,
    this.username,
    this.photoURL,
  });

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) {
    return UserProfile(
      id: id,
      username: data['username'] as String?,
      photoURL: data['photoURL'] as String?,
    );
  }
} 