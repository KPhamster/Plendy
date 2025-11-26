class UserProfile {
  final String id;
  final String? username;
  final String? displayName;
  final String? photoURL;
  final String? bio;
  final bool isPrivate;
  final int? timezoneOffsetMinutes; // Timezone offset from UTC in minutes

  UserProfile({
    required this.id,
    this.username,
    this.displayName,
    this.photoURL,
    this.bio,
    this.isPrivate = false,
    this.timezoneOffsetMinutes,
  });

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) {
    return UserProfile(
      id: id,
      username: data['username'] as String?,
      displayName: data['displayName'] as String?,
      photoURL: data['photoURL'] as String?,
      bio: data['bio'] as String?,
      isPrivate: data['isPrivate'] as bool? ?? false,
      timezoneOffsetMinutes: data['timezoneOffsetMinutes'] as int?,
    );
  }
}
