class UserProfile {
  final String id;
  final String? username;
  final String? displayName;
  final String? photoURL;
  final bool isPrivate;

  UserProfile({
    required this.id,
    this.username,
    this.displayName,
    this.photoURL,
    this.isPrivate = false,
  });

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) {
    return UserProfile(
      id: id,
      username: data['username'] as String?,
      displayName: data['displayName'] as String?,
      photoURL: data['photoURL'] as String?,
      isPrivate: data['isPrivate'] as bool? ?? false,
    );
  }
} 