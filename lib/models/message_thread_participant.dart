class MessageThreadParticipant {
  final String id;
  final String? username;
  final String? displayName;
  final String? photoUrl;

  const MessageThreadParticipant({
    required this.id,
    this.username,
    this.displayName,
    this.photoUrl,
  });

  factory MessageThreadParticipant.fromMap(
      String id, Map<String, dynamic>? data) {
    if (data == null) {
      return MessageThreadParticipant(id: id);
    }
    return MessageThreadParticipant(
      id: id,
      username: data['username'] as String?,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'displayName': displayName,
      'photoUrl': photoUrl,
    };
  }

  String displayLabel({String fallback = 'Unknown'}) {
    if (displayName?.isNotEmpty == true) {
      return displayName!;
    }
    if (username?.isNotEmpty == true) {
      return '@' + username!;
    }
    return fallback;
  }
}
