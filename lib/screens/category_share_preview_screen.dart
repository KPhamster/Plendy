import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:provider/provider.dart';
import '../../firebase_options.dart';
import '../models/experience.dart';
import '../services/experience_service.dart';
import '../services/auth_service.dart';
import '../services/category_share_service.dart';
import '../providers/category_save_progress_notifier.dart';
import 'auth_screen.dart';
import 'main_screen.dart';
import '../config/category_share_preview_help_content.dart';
import '../models/category_share_preview_help_target.dart';
import '../widgets/screen_help_controller.dart';

class CategorySharePreviewScreen extends StatefulWidget {
  final String token;

  const CategorySharePreviewScreen({super.key, required this.token});

  @override
  State<CategorySharePreviewScreen> createState() =>
      _CategorySharePreviewScreenState();
}

class _CategorySharePreviewScreenState extends State<CategorySharePreviewScreen>
    with TickerProviderStateMixin {
  late final ScreenHelpController<CategorySharePreviewHelpTargetId> _help;

  @override
  void initState() {
    super.initState();
    _help = ScreenHelpController<CategorySharePreviewHelpTargetId>(
      vsync: this,
      content: categorySharePreviewHelpContent,
      setState: setState,
      isMounted: () => mounted,
      defaultFirstTarget: CategorySharePreviewHelpTargetId.helpButton,
    );
    if (kIsWeb) {
      _tryOpenInAppOnIOS();
    }
  }

  @override
  void dispose() {
    _help.dispose();
    super.dispose();
  }

  void _tryOpenInAppOnIOS() {
    // Inject JavaScript to detect iOS and attempt app opening
    // This runs once when the web page loads
    if (kIsWeb) {
      // ignore: undefined_prefixed_name
      // dart:html is only available on web
      try {
        // Use a small delay to ensure page has loaded
        Future.delayed(const Duration(milliseconds: 500), () {
          // This will be handled by JavaScript in index.html
          // We'll add a meta tag to trigger the app opening
        });
      } catch (e) {
        // Silently fail if not on web
      }
    }
  }

  void _navigateToMain(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _navigateToMain(context);
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_help.tryTap(
                      CategorySharePreviewHelpTargetId.previewView, context)) {
                    return;
                  }
                  _navigateToMain(context);
                },
              ),
              title:
                  const Text('Shared Category', style: TextStyle(fontSize: 16)),
              actions: [
                if (kIsWeb)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: TextButton.icon(
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.black),
                      icon: const Icon(Icons.open_in_new, color: Colors.black),
                      label: const Text('Open in Plendy',
                          style: TextStyle(color: Colors.black)),
                      onPressed: () {
                        if (_help.tryTap(
                            CategorySharePreviewHelpTargetId.previewView,
                            context)) {
                          return;
                        }
                        _handleOpenInApp(context);
                      },
                    ),
                  ),
                _help.buildIconButton(inactiveColor: Colors.black87),
              ],
              bottom: _help.isActive
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(24),
                      child: _help.buildExitBanner(),
                    )
                  : null,
            ),
            body: GestureDetector(
              behavior: _help.isActive
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.deferToChild,
              onTap: _help.isActive
                  ? () => _help.tryTap(
                        CategorySharePreviewHelpTargetId.previewView,
                        context,
                      )
                  : null,
              child: IgnorePointer(
                ignoring: _help.isActive,
                child: FutureBuilder<_CategoryPreviewPayload>(
                  future: _fetchCategoryShare(widget.token),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                          child: Text('This share isn\'t available.'));
                    }
                    final payload = snapshot.data!;
                    if (payload.isMulti) {
                      return _MultiCategoryPreviewList(payload: payload);
                    }
                    return _CategoryPreviewList(
                      title: payload.categoryTitle,
                      iconOrColor: payload.iconOrColor,
                      experiences: payload.experiencesFuture,
                      fromUserId: payload.fromUserId,
                      accessMode: payload.accessMode,
                      categoryId: payload.categoryId,
                      isColorCategory: payload.isColorCategory,
                    );
                  },
                ),
              ),
            ),
          ),
          if (_help.isActive && _help.hasActiveTarget) _help.buildOverlay(),
        ],
      ),
    );
  }

  Future<void> _handleOpenInApp(BuildContext context) async {
    final Uri deepLink =
        Uri.parse('https://plendy.app/shared-category/${widget.token}');

    // On web, we need to handle Universal Links differently to avoid opening both app and browser
    if (kIsWeb) {
      // Try to open the app directly without opening a new browser tab
      final bool launched = await launchUrl(
        deepLink,
        mode: LaunchMode.platformDefault, // Let the platform decide
        webOnlyWindowName:
            '_self', // Replace current tab instead of opening new one
      );

      if (!launched) {
        // If app doesn't open, show a message
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please install the Plendy app to open this link'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      // On mobile, this should not be called, but handle it anyway
      final bool launchedDeepLink = await launchUrl(
        deepLink,
        mode: LaunchMode.externalApplication,
      );
      if (!launchedDeepLink) {
        await launchUrl(Uri.parse('https://plendy.app'));
      }
    }
  }

  Future<_CategoryPreviewPayload> _fetchCategoryShare(String token) async {
    // Query Firestore REST for document in 'category_shares' with token
    const projectId = 'plendy-7df50';
    // Small stabilization delay on mobile to allow network/AppCheck to warm up on cold starts
    if (!kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 250));
    }

    // DNS warm-up to avoid UnknownHostException on cold start
    Future<void> waitForDns(String host) async {
      const List<int> delays = [100, 200, 300, 500, 800, 1200, 1800];
      for (final d in delays) {
        try {
          final res = await InternetAddress.lookup(host);
          if (res.isNotEmpty && res.first.rawAddress.isNotEmpty) {
            return; // resolved
          }
        } catch (_) {
          // ignore and retry
        }
        await Future.delayed(Duration(milliseconds: d));
      }
    }

    if (!kIsWeb) {
      await waitForDns('firestore.googleapis.com');
    }
    final runQueryUrl = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents:runQuery');
    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance.getToken(true);
    } catch (_) {
      // App Check token fetch can fail during cold start without connectivity; continue without it
    }
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (apiKey.isNotEmpty) 'x-goog-api-key': apiKey,
      if (appCheckToken != null && appCheckToken.isNotEmpty)
        'X-Firebase-AppCheck': appCheckToken,
    };
    // Helper: basic retry with backoff for GET/POST
    Future<http.Response?> retryHttp(
      Future<http.Response> Function() send,
    ) async {
      const List<int> delays = [200, 400, 800, 1200, 1800, 2500, 3500];
      http.Response? lastResp;
      for (int i = 0; i < delays.length; i++) {
        try {
          final r = await send();
          lastResp = r;
          if (r.statusCode == 200) return r;
          // Retry on transient errors
          if ([408, 429, 500, 502, 503, 504].contains(r.statusCode)) {
            await Future.delayed(Duration(milliseconds: delays[i]));
            continue;
          }
          // Non-retriable error
          return r;
        } catch (e) {
          // Retry on common network exceptions
          final isNet = e is SocketException ||
              e is http.ClientException ||
              (e is HandshakeException);
          if (i < delays.length - 1 && isNet) {
            await Future.delayed(Duration(milliseconds: delays[i]));
            continue;
          }
          rethrow;
        }
      }
      return lastResp;
    }

    // Fast path: fetch by document id (we save share at category_shares/{token})
    final byIdUrl = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/category_shares/$token');
    try {
      http.Response? byIdResp =
          await retryHttp(() => http.get(byIdUrl, headers: headers));
      // If not found immediately, wait briefly and try byId one more time to avoid propagation races
      if (byIdResp != null && byIdResp.statusCode == 404 && !kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 600));
        byIdResp = await retryHttp(() => http.get(byIdUrl, headers: headers));
      }
      if (byIdResp != null && byIdResp.statusCode == 200) {
        final body = json.decode(byIdResp.body) as Map<String, dynamic>;
        final mapped = _mapRestDoc(body);
        return _payloadFromMapped(mapped);
      }
    } catch (_) {
      // Ignore and fall through to query path
    }

    final payload = {
      'structuredQuery': {
        'from': [
          {'collectionId': 'category_shares'}
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'token'},
                  'op': 'EQUAL',
                  'value': {'stringValue': token}
                }
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'visibility'},
                  'op': 'IN',
                  'value': {
                    'arrayValue': {
                      'values': [
                        {'stringValue': 'public'},
                        {'stringValue': 'unlisted'}
                      ]
                    }
                  }
                }
              }
            ]
          }
        },
        'limit': 1
      }
    };
    // Retry the query a few times to be resilient to transient DNS/connectivity issues
    http.Response? resp;
    try {
      resp = await retryHttp(() =>
          http.post(runQueryUrl, body: json.encode(payload), headers: headers));
    } catch (e) {
      throw Exception('Network error while looking up share');
    }
    if (resp == null) {
      throw Exception('Share lookup failed');
    }

    List results = json.decode(resp.body) as List;
    Map<String, dynamic>? first = results
        .cast<Map<String, dynamic>?>()
        .firstWhere((e) => e != null && e.containsKey('document'),
            orElse: () => null);
    if (first == null) {
      // Cold-start race or transient propagation; retry a couple more times with backoff
      for (final delay in [700, 1200]) {
        await Future.delayed(Duration(milliseconds: delay));
        final retry = await retryHttp(() => http.post(runQueryUrl,
            body: json.encode(payload), headers: headers));
        if (retry != null && retry.statusCode == 200) {
          results = json.decode(retry.body) as List;
          first = results.cast<Map<String, dynamic>?>().firstWhere(
              (e) => e != null && e.containsKey('document'),
              orElse: () => null);
          if (first != null) break;
        }
      }
      if (first == null) throw Exception('Share not found');
    }
    final mapped = _mapRestDoc(first['document'] as Map<String, dynamic>);
    return _payloadFromMapped(mapped);
  }

  Map<String, dynamic> _mapRestDoc(Map<String, dynamic> docJson) {
    final fields = (docJson['fields'] ?? {}) as Map<String, dynamic>;

    dynamic val(Map<String, dynamic>? v) {
      if (v == null) return null;
      if (v.containsKey('stringValue')) return v['stringValue'];
      if (v.containsKey('integerValue')) {
        return int.tryParse(v['integerValue'] as String);
      }
      if (v.containsKey('doubleValue')) {
        return (v['doubleValue'] as num).toDouble();
      }
      if (v.containsKey('booleanValue')) return v['booleanValue'] as bool;
      if (v.containsKey('mapValue')) {
        final m =
            (v['mapValue']['fields'] as Map<String, dynamic>?) ?? const {};
        return m.map((k, vv) => MapEntry(k, val(vv as Map<String, dynamic>?)));
      }
      if (v.containsKey('arrayValue')) {
        final list = (v['arrayValue']['values'] as List?) ?? const [];
        return list.map((e) => val(e as Map<String, dynamic>?)).toList();
      }
      return null;
    }

    Map<String, dynamic> decoded =
        fields.map((k, v) => MapEntry(k, val(v as Map<String, dynamic>?)));
    return decoded;
  }

  Future<List<Experience>> _fetchExperiencesForCategory({
    required bool isColorCategory,
    required String categoryId,
  }) async {
    final service = ExperienceService();
    if (isColorCategory) {
      return service.getExperiencesByColorCategoryId(categoryId);
    }
    return service.getExperiencesByUserCategoryId(categoryId);
  }

  _CategoryPreviewPayload _payloadFromMapped(Map<String, dynamic> mapped) {
    final String? categoryType =
        mapped['categoryType'] as String?; // 'user' | 'color' | 'multi'
    final bool isMulti = categoryType == 'multi';
    final bool isColor = categoryType == 'color';
    final String categoryId = ((isColor
            ? mapped['colorCategoryId']
            : mapped['categoryId']) as String?) ??
        '';
    final Map<String, dynamic>? snapshot =
        mapped['snapshot'] as Map<String, dynamic>?;
    final String title = (snapshot?['name'] as String?) ??
        (isColor ? 'Color Category' : 'Category');
    final dynamic iconOrColor = isColor
        ? (snapshot != null ? snapshot['color'] : null)
        : (snapshot != null ? snapshot['icon'] : null);

    if (!isMulti) {
      // Single category path
      final List<dynamic> expSnaps =
          (snapshot?['experiences'] as List?) ?? const [];
      final List<_ExperiencePreview> embedded = expSnaps
          .whereType<Map<String, dynamic>>()
          .map((m) => _experienceFromSnapshot(m))
          .toList();

      final Future<List<_ExperiencePreview>> experiencesFuture = embedded
              .isNotEmpty
          ? Future.value(embedded)
          : _fetchExperiencesForCategory(
                  isColorCategory: isColor, categoryId: categoryId)
              .then(
                  (list) => list.map((e) => _experienceFromModel(e)).toList());

      return _CategoryPreviewPayload(
        categoryTitle: title,
        iconOrColor: iconOrColor,
        categoryId: categoryId,
        isColorCategory: isColor,
        experiencesFuture: experiencesFuture,
        fromUserId: (mapped['fromUserId'] as String?) ?? '',
        accessMode: (mapped['accessMode'] as String?) ?? 'view',
      );
    }

    // Multi-category path
    final List userCats = (snapshot?['userCategories'] as List?) ?? const [];
    final List colorCats = (snapshot?['colorCategories'] as List?) ?? const [];
    final List<_MultiCategoryItem> items = [];
    for (final m in userCats.whereType<Map<String, dynamic>>()) {
      final List<dynamic> expSnaps = (m['experiences'] as List?) ?? const [];
      final embedded = expSnaps
          .whereType<Map<String, dynamic>>()
          .map((e) => _experienceFromSnapshot(e))
          .toList();
      items.add(_MultiCategoryItem(
        id: (m['id'] as String?) ?? '',
        title: (m['name'] as String?) ?? 'Category',
        isColor: false,
        iconOrColor: m['icon'],
        experiences: embedded,
      ));
    }
    for (final m in colorCats.whereType<Map<String, dynamic>>()) {
      final List<dynamic> expSnaps = (m['experiences'] as List?) ?? const [];
      final embedded = expSnaps
          .whereType<Map<String, dynamic>>()
          .map((e) => _experienceFromSnapshot(e))
          .toList();
      items.add(_MultiCategoryItem(
        id: (m['id'] as String?) ?? '',
        title: (m['name'] as String?) ?? 'Color Category',
        isColor: true,
        iconOrColor: m['color'],
        experiences: embedded,
      ));
    }

    return _CategoryPreviewPayload.multi(
      items: items,
      fromUserId: (mapped['fromUserId'] as String?) ?? '',
      accessMode: (mapped['accessMode'] as String?) ?? 'view',
    );
  }
}

class _CategoryPreviewPayload {
  final String categoryTitle;
  final dynamic
      iconOrColor; // String icon when user category, int color value when color
  final String categoryId;
  final bool isColorCategory;
  final Future<List<_ExperiencePreview>> experiencesFuture;
  final String fromUserId;
  final String accessMode;
  final bool isMulti;
  final List<_MultiCategoryItem>? items;

  _CategoryPreviewPayload({
    required this.categoryTitle,
    required this.iconOrColor,
    required this.categoryId,
    required this.isColorCategory,
    required this.experiencesFuture,
    required this.fromUserId,
    required this.accessMode,
  })  : isMulti = false,
        items = null;

  _CategoryPreviewPayload.multi({
    required List<_MultiCategoryItem> items,
    required this.fromUserId,
    required this.accessMode,
  })  : categoryTitle = 'Multiple Categories',
        iconOrColor = null,
        categoryId = '',
        isColorCategory = false,
        experiencesFuture = Future.value(const <_ExperiencePreview>[]),
        isMulti = true,
        items = items;
}

class _CategoryPreviewList extends StatefulWidget {
  final String title;
  final dynamic iconOrColor;
  final Future<List<_ExperiencePreview>> experiences;
  final String fromUserId;
  final String accessMode;
  final String categoryId;
  final bool isColorCategory;

  const _CategoryPreviewList({
    required this.title,
    required this.iconOrColor,
    required this.experiences,
    required this.fromUserId,
    required this.accessMode,
    required this.categoryId,
    required this.isColorCategory,
  });

  @override
  State<_CategoryPreviewList> createState() => _CategoryPreviewListState();
}

class _CategoryPreviewListState extends State<_CategoryPreviewList> {
  String? _senderDisplayName;
  bool _isLoggedIn = false;
  bool _isLoadingUserInfo = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    if (mounted) {
      setState(() {
        _isLoadingUserInfo = true;
      });
    }
    try {
      // Check if user is logged in
      final authService = AuthService();
      final currentUser = authService.currentUser;
      final isLoggedIn = currentUser != null;

      // Fetch sender's display name
      String? displayName;
      if (widget.fromUserId.isNotEmpty) {
        final experienceService = ExperienceService();
        final userProfile =
            await experienceService.getUserProfileById(widget.fromUserId);
        displayName =
            userProfile?.displayName ?? userProfile?.username ?? 'Someone';
      }

      if (mounted) {
        setState(() {
          _isLoggedIn = isLoggedIn;
          _senderDisplayName = displayName;
          _isLoadingUserInfo = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _senderDisplayName = 'Someone';
          _isLoadingUserInfo = false;
        });
      }
    }
  }

  String _getBannerText() {
    final senderName = _senderDisplayName ?? 'Someone';
    final mode = widget.accessMode.toLowerCase();
    if (mode == 'view') {
      if (_isLoggedIn) {
        return "Check out $senderName's experience list! Save the list to get view-only access.";
      } else {
        return "Check out $senderName's experience list! Log into Plendy to get view-only access.";
      }
    }
    const editModes = {'edit', 'edit_category', 'edit_color_category'};
    if (editModes.contains(mode)) {
      return "Check out $senderName's experience list! Save the list to get edit access.";
    }
    return "Check out $senderName's experience list!";
  }

  Future<void> _handleSaveCategory() async {
    if (_isSaving) {
      return;
    }

    setState(() => _isSaving = true);

    final AuthService authService = AuthService();
    String? currentUserId = authService.currentUser?.uid;

    if (currentUserId == null) {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (!mounted) {
        return;
      }
      await _loadUserInfo();
      currentUserId = authService.currentUser?.uid;
      if (currentUserId == null) {
        setState(() => _isSaving = false);
        return;
      }
    }

    if (widget.categoryId.isEmpty || widget.fromUserId.isEmpty) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to save this category right now.')),
        );
      }
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final CategorySaveProgressNotifier notifier =
        Provider.of<CategorySaveProgressNotifier>(context, listen: false);
    final CategoryShareService service = CategoryShareService();
    final ExperienceService experienceService = ExperienceService();
    final String targetUserId = currentUserId;
    final String categoryId = widget.categoryId;
    final String fromUserId = widget.fromUserId;
    final String accessMode = widget.accessMode;
    final String categoryName = widget.title;
    final bool isColorCategory = widget.isColorCategory;

    unawaited(() async {
      try {
        final experienceIds = await _fetchExperienceIdsForOwner(
          experienceService: experienceService,
          ownerUserId: fromUserId,
          categoryId: categoryId,
          isColorCategory: isColorCategory,
          previewFuture: widget.experiences,
        );
        final int totalUnits = 1 + experienceIds.length;

        notifier.startCategorySave(
          categoryName: categoryName,
          totalUnits: totalUnits,
          categoryId: categoryId,
          ownerUserId: fromUserId,
          isColorCategory: isColorCategory,
          accessMode: accessMode,
          experienceIds: experienceIds,
          maxRetries: 1,
          saveOperation: (controller) async {
            await service.grantSharedCategoryToUser(
              categoryId: categoryId,
              ownerUserId: fromUserId,
              targetUserId: targetUserId,
              accessMode: accessMode,
              experienceIds: experienceIds,
              onProgress: (completed, total) {
                controller.update(
                  completedUnits: completed,
                  totalUnits: total,
                );
              },
            );
          },
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to save category: $e')),
        );
      }
    }());

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner text for share notification
        if (!_isLoadingUserInfo)
          Container(
            width: double.infinity,
            color: Colors.blue[50],
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _getBannerText(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.blue[800],
                    fontWeight: FontWeight.w500,
                  ),
              textAlign: TextAlign.center,
              softWrap: true,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              if (widget.iconOrColor is String)
                Text(widget.iconOrColor as String,
                    style: const TextStyle(fontSize: 24))
              else if (widget.iconOrColor is int)
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Color(widget.iconOrColor as int),
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isSaving ? null : _handleSaveCategory,
                child: Text(_isSaving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<_ExperiencePreview>>(
            future: widget.experiences,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? const <_ExperiencePreview>[];
              if (items.isEmpty) {
                return const Center(
                    child: Text('No experiences in this category.'));
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final exp = items[index];
                  return ListTile(
                    title: Text(exp.title),
                    subtitle: Text(exp.subtitle ?? ''),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MultiCategoryItem {
  final String id;
  final String title;
  final bool isColor;
  final dynamic iconOrColor; // icon (String) or color (int)
  final List<_ExperiencePreview> experiences;

  _MultiCategoryItem({
    required this.id,
    required this.title,
    required this.isColor,
    required this.iconOrColor,
    required this.experiences,
  });
}

class _MultiCategoryPreviewList extends StatefulWidget {
  final _CategoryPreviewPayload payload;

  const _MultiCategoryPreviewList({required this.payload});

  @override
  State<_MultiCategoryPreviewList> createState() =>
      _MultiCategoryPreviewListState();
}

class _MultiCategoryPreviewListState extends State<_MultiCategoryPreviewList> {
  bool _isSaving = false;
  bool _isLoggedIn = false;
  String? _senderDisplayName;
  bool _isLoadingUserInfo = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    if (mounted) setState(() => _isLoadingUserInfo = true);
    try {
      final authService = AuthService();
      final currentUser = authService.currentUser;
      final isLoggedIn = currentUser != null;
      String? displayName;
      if (widget.payload.fromUserId.isNotEmpty) {
        final experienceService = ExperienceService();
        final userProfile = await experienceService
            .getUserProfileById(widget.payload.fromUserId);
        displayName =
            userProfile?.displayName ?? userProfile?.username ?? 'Someone';
      }
      if (mounted) {
        setState(() {
          _isLoggedIn = isLoggedIn;
          _senderDisplayName = displayName;
          _isLoadingUserInfo = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUserInfo = false);
    }
  }

  String _getBannerText() {
    final senderName = _senderDisplayName ?? 'Someone';
    final mode = widget.payload.accessMode.toLowerCase();
    if (mode == 'view') {
      return _isLoggedIn
          ? "Check out $senderName's categories! Save to get view-only access."
          : "Check out $senderName's categories! Log in to get view-only access.";
    }
    const editModes = {'edit', 'edit_category', 'edit_color_category'};
    if (editModes.contains(mode)) {
      return "Check out $senderName's categories! Save to get edit access.";
    }
    return "Check out $senderName's categories!";
  }

  Future<void> _handleSaveAll() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    final AuthService authService = AuthService();
    String? currentUserId = authService.currentUser?.uid;
    if (currentUserId == null) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (!mounted) return;
      await _loadUserInfo();
      currentUserId = authService.currentUser?.uid;
      if (currentUserId == null) {
        setState(() => _isSaving = false);
        return;
      }
    }

    final List<_MultiCategoryItem> items =
        widget.payload.items ?? const <_MultiCategoryItem>[];
    if (items.isEmpty) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to save these categories right now.')),
        );
      }
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final CategorySaveProgressNotifier notifier =
        Provider.of<CategorySaveProgressNotifier>(context, listen: false);
    final CategoryShareService service = CategoryShareService();
    final ExperienceService experienceService = ExperienceService();
    final String targetUserId = currentUserId;
    final String fromUserId = widget.payload.fromUserId;
    final String accessMode = widget.payload.accessMode;

    unawaited(() async {
      for (final _MultiCategoryItem item in items) {
        if (item.id.isEmpty) {
          continue;
        }
        try {
          final experienceIds = await _fetchExperienceIdsForOwner(
            experienceService: experienceService,
            ownerUserId: fromUserId,
            categoryId: item.id,
            isColorCategory: item.isColor,
            snapshotExperiences: item.experiences,
          );
          final int totalUnits = 1 + experienceIds.length;

          notifier.startCategorySave(
            categoryName: item.title,
            totalUnits: totalUnits,
            categoryId: item.id,
            ownerUserId: fromUserId,
            isColorCategory: item.isColor,
            accessMode: accessMode,
            experienceIds: experienceIds,
            maxRetries: 1,
            saveOperation: (controller) async {
              await service.grantSharedCategoryToUser(
                categoryId: item.id,
                ownerUserId: fromUserId,
                targetUserId: targetUserId,
                accessMode: accessMode,
                experienceIds: experienceIds,
                onProgress: (completed, total) {
                  controller.update(
                    completedUnits: completed,
                    totalUnits: total,
                  );
                },
              );
            },
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('Failed to save ${item.title}: $e')),
          );
        }
      }
    }());

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.payload.items ?? const <_MultiCategoryItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_isLoadingUserInfo)
          Container(
            width: double.infinity,
            color: Colors.blue[50],
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _getBannerText(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.blue[800],
                    fontWeight: FontWeight.w500,
                  ),
              textAlign: TextAlign.center,
              softWrap: true,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text('Shared Categories',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isSaving ? null : _handleSaveAll,
                child: Text(_isSaving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ExpansionTile(
                title: Row(
                  children: [
                    if (!item.isColor && item.iconOrColor is String)
                      Text(item.iconOrColor as String,
                          style: const TextStyle(fontSize: 20)),
                    if (item.isColor && item.iconOrColor is int)
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Color(item.iconOrColor as int),
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.title,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ],
                ),
                subtitle: Text(item.isColor ? 'Color Category' : 'Category'),
                children: [
                  if (item.experiences.isEmpty)
                    const ListTile(
                      title: Text('No experiences in this category.'),
                    )
                  else
                    ...item.experiences.map((e) => ListTile(
                          dense: true,
                          title: Text(e.title),
                          subtitle: Text(e.subtitle ?? ''),
                        )),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExperiencePreview {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;

  _ExperiencePreview(
      {required this.id, required this.title, this.subtitle, this.imageUrl});
}

_ExperiencePreview _experienceFromSnapshot(Map<String, dynamic> snap) {
  final loc = (snap['location'] as Map<String, dynamic>?) ?? const {};
  final List imageUrls = (snap['imageUrls'] as List?) ?? const [];
  return _ExperiencePreview(
    id: (snap['experienceId'] as String?) ?? '',
    title: (snap['name'] as String?) ?? 'Experience',
    subtitle: (loc['address'] as String?) ?? loc['displayName'] as String?,
    imageUrl: imageUrls.isNotEmpty ? imageUrls.first.toString() : null,
  );
}

_ExperiencePreview _experienceFromModel(Experience e) {
  return _ExperiencePreview(
    id: e.id,
    title: e.name,
    subtitle: e.location.address ?? e.location.displayName,
    imageUrl: e.imageUrls.isNotEmpty ? e.imageUrls.first : null,
  );
}

Future<List<String>> _fetchExperienceIdsForOwner({
  required ExperienceService experienceService,
  required String ownerUserId,
  required String categoryId,
  required bool isColorCategory,
  Future<List<_ExperiencePreview>>? previewFuture,
  List<_ExperiencePreview>? snapshotExperiences,
}) async {
  if (ownerUserId.isEmpty || categoryId.isEmpty) {
    return <String>[];
  }
  List<String> experienceIds = <String>[];
  try {
    final ownerExperiences =
        await experienceService.getExperiencesForOwnerCategory(
      ownerUserId: ownerUserId,
      categoryId: categoryId,
      isColorCategory: isColorCategory,
    );
    experienceIds = ownerExperiences
        .map((exp) => exp.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  } catch (_) {
    // Ignore and fall back to provided snapshots.
  }

  if (experienceIds.isNotEmpty) {
    return experienceIds;
  }

  if (previewFuture != null) {
    final previews = await previewFuture;
    return previews
        .map((exp) => exp.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  if (snapshotExperiences != null) {
    return snapshotExperiences
        .map((exp) => exp.id)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  return <String>[];
}
