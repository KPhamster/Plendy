import '../models/user_profile.dart';

/// Result from a direct share operation containing the thread IDs
/// that were used to send the share messages.
class DirectShareResult {
  /// List of thread IDs where the share was sent
  final List<String> threadIds;

  /// Recipient profiles when there's a single recipient (for personalized messaging)
  final List<UserProfile> recipientProfiles;

  const DirectShareResult({
    required this.threadIds,
    this.recipientProfiles = const [],
  });

  /// Whether there is at least one thread to navigate to
  bool get hasThreads => threadIds.isNotEmpty;

  /// Get the first thread ID (useful when navigating to a single thread)
  String? get firstThreadId => threadIds.isNotEmpty ? threadIds.first : null;

  /// Whether this is a single recipient share
  bool get isSingleRecipient => recipientProfiles.length == 1;

  /// Get the display name for single recipient sharing
  String? get singleRecipientDisplayName => isSingleRecipient
      ? recipientProfiles.first.displayName ?? recipientProfiles.first.username ?? 'Friend'
      : null;

  /// Create a DirectShareResult from a single thread ID
  factory DirectShareResult.single(String threadId, {List<UserProfile> recipientProfiles = const []}) => DirectShareResult(
        threadIds: [threadId],
        recipientProfiles: recipientProfiles,
      );

  /// Create a DirectShareResult from multiple thread IDs
  factory DirectShareResult.multiple(List<String> threadIds, {List<UserProfile> recipientProfiles = const []}) => DirectShareResult(
        threadIds: threadIds,
        recipientProfiles: recipientProfiles,
      );
}

