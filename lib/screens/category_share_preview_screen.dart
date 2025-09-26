import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../firebase_options.dart';
import '../models/experience.dart';
import '../services/experience_service.dart';
import '../services/auth_service.dart';
import '../services/category_share_service.dart';
import 'auth_screen.dart';
import 'main_screen.dart';

class CategorySharePreviewScreen extends StatelessWidget {
  final String token;

  const CategorySharePreviewScreen({super.key, required this.token});

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
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _navigateToMain(context),
          ),
          title: const Text('Shared Category', style: TextStyle(fontSize: 16)),
          actions: [
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.black),
                  icon: const Icon(Icons.open_in_new, color: Colors.black),
                  label: const Text('Open in Plendy',
                      style: TextStyle(color: Colors.black)),
                  onPressed: () => _handleOpenInApp(context),
                ),
              ),
          ],
        ),
        body: FutureBuilder<_CategoryPreviewPayload>(
          future: _fetchCategoryShare(token),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: Text('This share isn\'t available.'));
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
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleOpenInApp(BuildContext context) async {
    final Uri deepLink =
        Uri.parse('https://plendy.app/shared-category/' + token);
    final bool launchedDeepLink = await launchUrl(
      deepLink,
      mode: LaunchMode.externalApplication,
    );
    if (launchedDeepLink) return;
    await launchUrl(Uri.parse('https://plendy.app'));
  }

  Future<_CategoryPreviewPayload> _fetchCategoryShare(String token) async {
    // Query Firestore REST for document in 'category_shares' with token
    const projectId = 'plendy-7df50';
    // Small stabilization delay on mobile to allow network/AppCheck to warm up on cold starts
    if (!kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 250));
    }

    // DNS warm-up to avoid UnknownHostException on cold start
    Future<void> _waitForDns(String host) async {
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
      await _waitForDns('firestore.googleapis.com');
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
    Future<http.Response?> _retryHttp(
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
          await _retryHttp(() => http.get(byIdUrl, headers: headers));
      // If not found immediately, wait briefly and try byId one more time to avoid propagation races
      if (byIdResp != null && byIdResp.statusCode == 404 && !kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 600));
        byIdResp = await _retryHttp(() => http.get(byIdUrl, headers: headers));
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
      resp = await _retryHttp(() =>
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
        final retry = await _retryHttp(() => http.post(runQueryUrl,
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

    dynamic _val(Map<String, dynamic>? v) {
      if (v == null) return null;
      if (v.containsKey('stringValue')) return v['stringValue'];
      if (v.containsKey('integerValue'))
        return int.tryParse(v['integerValue'] as String);
      if (v.containsKey('doubleValue'))
        return (v['doubleValue'] as num).toDouble();
      if (v.containsKey('booleanValue')) return v['booleanValue'] as bool;
      if (v.containsKey('mapValue')) {
        final m =
            (v['mapValue']['fields'] as Map<String, dynamic>?) ?? const {};
        return m.map((k, vv) => MapEntry(k, _val(vv as Map<String, dynamic>?)));
      }
      if (v.containsKey('arrayValue')) {
        final list = (v['arrayValue']['values'] as List?) ?? const [];
        return list.map((e) => _val(e as Map<String, dynamic>?)).toList();
      }
      return null;
    }

    Map<String, dynamic> decoded =
        fields.map((k, v) => MapEntry(k, _val(v as Map<String, dynamic>?)));
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
              .then((list) => list.map((e) => _experienceFromModel(e)).toList());

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
    this.isMulti = false,
    this.items,
  });

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

  const _CategoryPreviewList({
    required this.title,
    required this.iconOrColor,
    required this.experiences,
    required this.fromUserId,
    required this.accessMode,
    required this.categoryId,
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

    final authService = AuthService();
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
        return;
      }
    }

    if (widget.categoryId.isEmpty || widget.fromUserId.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Unable to save this category right now.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final previews = await widget.experiences;
      final experienceIds = previews
          .map((exp) => exp.id)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final service = CategoryShareService();
      await service.grantSharedCategoryToUser(
        categoryId: widget.categoryId,
        ownerUserId: widget.fromUserId,
        targetUserId: currentUserId,
        accessMode: widget.accessMode,
        experienceIds: experienceIds,
      );

      if (!mounted) {
        return;
      }

      final accessLabel =
          widget.accessMode.toLowerCase() == 'edit' ? 'edit' : 'view';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category saved with $accessLabel access.')),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save category: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
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
  State<_MultiCategoryPreviewList> createState() => _MultiCategoryPreviewListState();
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
        final userProfile =
            await experienceService.getUserProfileById(widget.payload.fromUserId);
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
    final authService = AuthService();
    String? currentUserId = authService.currentUser?.uid;
    if (currentUserId == null) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (!mounted) return;
      await _loadUserInfo();
      currentUserId = authService.currentUser?.uid;
      if (currentUserId == null) return;
    }

    setState(() => _isSaving = true);
    try {
      final service = CategoryShareService();
      final List<String> experienceIds = widget.payload.items!
          .expand((i) => i.experiences.map((e) => e.id))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      // Grant for each category separately
      for (final item in widget.payload.items!) {
        await service.grantSharedCategoryToUser(
          categoryId: item.id,
          ownerUserId: widget.payload.fromUserId,
          targetUserId: currentUserId!,
          accessMode: widget.payload.accessMode,
          experienceIds: experienceIds,
        );
      }

      if (!mounted) return;
      final accessLabel =
          widget.payload.accessMode.toLowerCase() == 'edit' ? 'edit' : 'view';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${widget.payload.items!.length} categories with $accessLabel access.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
