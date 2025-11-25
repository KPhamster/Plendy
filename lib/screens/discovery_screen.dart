import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/color_category.dart';
import '../models/experience.dart';
import '../models/public_experience.dart';
import '../models/report.dart';
import '../models/shared_media_item.dart';
import '../models/user_category.dart';
import '../services/experience_service.dart';
import '../services/experience_share_service.dart';
import '../services/discovery_share_service.dart';
import '../services/google_maps_service.dart';
import '../services/report_service.dart';
import 'receive_share/widgets/facebook_preview_widget.dart';
import 'receive_share/widgets/generic_url_preview_widget.dart';
import 'receive_share/widgets/maps_preview_widget.dart';
import 'receive_share/widgets/tiktok_preview_widget.dart';
import 'receive_share/widgets/youtube_preview_widget.dart';
import 'receive_share/widgets/instagram_preview_widget.dart'
    as instagram_widget;
import '../widgets/save_to_experiences_modal.dart';
import 'experience_page_screen.dart';
import 'map_screen.dart';
import '../widgets/web_media_preview_card.dart';
import '../widgets/share_experience_bottom_sheet.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({
    super.key,
    this.initialShareToken,
  });

  final String? initialShareToken;

  @override
  State<DiscoveryScreen> createState() => DiscoveryScreenState();
}

class DiscoveryScreenState extends State<DiscoveryScreen>
    with AutomaticKeepAliveClientMixin {
  static const UserCategory _publicReadOnlyCategory = UserCategory(
    id: 'public_readonly_category',
    name: 'Discovery',
    icon: '*',
    ownerUserId: 'public',
  );

  final ExperienceService _experienceService = ExperienceService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final DiscoveryShareService _discoveryShareService = DiscoveryShareService();
  final ExperienceShareService _experienceShareService =
      ExperienceShareService();
  final ReportService _reportService = ReportService();
  final Map<String, Future<Map<String, dynamic>?>> _mapsPreviewFutures = {};
  final Map<String, Future<List<Experience>>> _linkedExperiencesFutures = {};
  final PageController _pageController = PageController();
  final Random _random = Random();
  static const String _seenMediaPrefsKey = 'discovery_seen_media_keys_v1';
  static const String _savedPlacesPrefsKey = 'discovery_saved_places_v1';
  static const String _savedMediaPrefsKey = 'discovery_saved_media_v1';
  static const Duration _cacheValidDuration = Duration(hours: 6);

  final List<PublicExperience> _publicExperiences = [];
  final List<_DiscoveryFeedItem> _feedItems = [];
  final Set<String> _usedMediaKeys = {};
  final Set<String> _persistedSeenMediaKeys = <String>{};
  final Set<String> _userSavedPlaceIds = <String>{};
  final Set<String> _userSavedMediaUrls = <String>{};
  List<UserCategory> _userCategories = [];
  List<ColorCategory> _userColorCategories = [];
  Future<void>? _userCollectionsFuture;
  Future<void>? _seenMediaLoadFuture;
  Future<void>? _userPlacesLoadFuture;
  SharedPreferences? _sharedPreferences;

  DocumentSnapshot<Object?>? _lastDocument;
  bool _hasMore = true;
  bool _isFetchingExperiences = false;
  bool _isLoading = true;
  bool _isError = false;
  bool _isPreparingMore = false;
  bool _isShareInProgress = false;
  bool _isLoadingSharedPreview = false;
  bool _hasStartedDiscovering = false;
  String? _errorMessage;
  int _currentPage = 0;
  double _dragDistance = 0;
  static const double _dragThreshold = 40;
  String? _lastDisplayedShareToken;
  // Firebase Storage folder containing the curated cover background images.
  static const String _coverBackgroundFolder = 'cover_photos';
  static const Duration _coverFadeDuration = Duration(milliseconds: 600);
  static const List<_CoverQuote> _coverQuotes = [
    _CoverQuote(
      text:
          'The world is full of magical things patiently waiting for our senses to grow sharper.',
      author: 'W.B. Yeats',
    ),
    _CoverQuote(
      text:
          'Life is short and the world is wide, so the sooner you start exploring it, the better.',
      author: 'Simon Raven',
    ),
    _CoverQuote(
      text:
          'Fill your life with experiences, not things. Have stories to tell, not stuff to show.',
      author: 'Abhysheq Shukla',
    ),
    _CoverQuote(
      text:
          'The world is a book, and those who do not travel read only one page.',
      author: 'Augustine of Hippo',
    ),
    _CoverQuote(
      text:
          'Not all those who wander are lost.',
      author: 'J.R.R. Tolkien',
    ),
    _CoverQuote(
      text:
          'Life is either a daring adventure or nothing at all.',
      author: 'Helen Keller',
    ),
     _CoverQuote(
      text:
          'Adventure is worthwhile in itself.',
      author: 'Amelia Earhart',
    ),
     _CoverQuote(
      text:
          'The journey of a thousand miles begins with a single step.',
      author: 'Lao Tzu',
    ),
     _CoverQuote(
      text:
          'To travel is to live.',
      author: 'Hans Christian Andersen',
    ),
     _CoverQuote(
      text:
          'Only those who will risk going too far can possibly find out how far one can go.',
      author: 'T.S. Eliot',
    ),
     _CoverQuote(
      text:
          'If you think adventure is dangerous, try routine; it is lethal.',
      author: 'Paulo Coelho',
    ),
    _CoverQuote(
      text:
          'Wanderer, there is no path; the path is made by walking.',
      author: 'Antonio Machado',
    ),
    _CoverQuote(
      text:
          'Wherever you go, go with all your heart.',
      author: 'Confucius',
    ),
    _CoverQuote(
      text:
          'The gladdest moment in human life, methinks, is a departure into unknown lands.',
      author: 'Richard Francis Burton',
    ),
    _CoverQuote(
      text:
          'One does not discover new lands without consenting to lose sight of the shore for a very long time.',
      author: 'André Gide',
    ),
    _CoverQuote(
      text:
          'I am not the same, having seen the moon shine on the other side of the world.',
      author: 'Mary Anne Radmacher',
    ),
    _CoverQuote(
      text:
          'Travel makes one modest; you see what a tiny place you occupy in the world.',
      author: 'Gustave Flaubert',
    ),
    _CoverQuote(
      text:
          'The mountains are calling and I must go.',
      author: 'John Muir',
    ),
     _CoverQuote(
      text:
          'In every walk with nature one receives far more than he seeks.',
      author: 'John Muir',
    ),
     _CoverQuote(
      text:
          'Go confidently in the direction of your dreams. Live the life you have imagined.',
      author: 'Henry David Thoreau',
    ),
     _CoverQuote(
      text:
          'Traveling — it leaves you speechless, then turns you into a storyteller.',
      author: 'Ibn Battuta',
    ),
     _CoverQuote(
      text:
          'The biggest adventure you can take is to live the life of your dreams.',
      author: 'Oprah Winfrey',
    ),
     _CoverQuote(
      text:
          'Because in the end, you won’t remember the time you spent working in an office… Climb that mountain.',
      author: 'Jack Kerouac',
    ),
     _CoverQuote(
      text:
          'Live in the sunshine, swim the sea, drink the wild air.',
      author: 'Ralph Waldo Emerson',
    ),
     _CoverQuote(
      text:
          'The clearest way into the Universe is through a forest wilderness.',
      author: 'John Muir',
    ),
     _CoverQuote(
      text:
          'To travel is to discover that everyone is wrong about other countries.',
      author: 'Aldous Huxley',
    ),
     _CoverQuote(
      text:
          'We live in a wonderful world that is full of beauty, charm and adventure.',
      author: 'Jawaharlal Nehru',
    ),
     _CoverQuote(
      text:
          'A ship in harbor is safe, but that is not what ships are built for.',
      author: 'John A. Shedd',
    ),
     _CoverQuote(
      text:
          'The use of traveling is to regulate imagination by reality.',
      author: 'Samuel Johnson',
    ),
     _CoverQuote(
      text:
          'Travel far enough, you meet yourself.',
      author: 'David Mitchell',
    ),
     _CoverQuote(
      text:
          'The very basic core of a man’s living spirit is his passion for adventure.',
      author: 'Christopher McCandless',
    ),
     _CoverQuote(
      text:
          'Twenty years from now you will be more disappointed by the things you didn’t do than by the ones you did do… Explore. Dream. Discover.',
      author: 'H. Jackson Brown Jr.',
    ),
     _CoverQuote(
      text:
          'Oh, the places you’ll go!',
      author: 'Dr. Seuss',
    ),
     _CoverQuote(
      text:
          'Exploration is really the essence of the human spirit.',
      author: 'Frank Borman',
    ),
     _CoverQuote(
      text:
          'Somewhere, something incredible is waiting to be known.',
      author: 'Carl Sagan',
    ),
     _CoverQuote(
      text:
          'To awaken quite alone in a strange town is one of the pleasantest sensations in the world.',
      author: 'Freya Stark',
    ),
     _CoverQuote(
      text:
          'The life you have led doesn’t need to be the only life you have.',
      author: 'Anna Quindlen',
    ),
     _CoverQuote(
      text:
          'If you’re offered a seat on a rocket ship, don’t ask what seat! Just get on.',
      author: 'Sheryl Sandberg',
    ),
     _CoverQuote(
      text:
          'You miss 100% of the shots you don’t take.',
      author: 'Wayne Gretzky',
    ),
     _CoverQuote(
      text:
          'I am always doing that which I cannot do, in order that I may learn how to do it.',
      author: 'Pablo Picasso',
    ),
     _CoverQuote(
      text:
          'What we fear doing most is usually what we most need to do.',
      author: 'Tim Ferriss',
    ),
     _CoverQuote(
      text:
          'Be brave enough to be bad at something new.',
      author: 'Jon Acuff',
    ),
     _CoverQuote(
      text:
          'We keep moving forward, opening new doors, and doing new things, because we’re curious.',
      author: 'Walt Disney',
    ),
     _CoverQuote(
      text:
          'Fortune favors the bold.',
      author: 'Virgil',
    ),
     _CoverQuote(
      text:
          'He who is not courageous enough to take risks will accomplish nothing in life.',
      author: 'Muhammad Ali',
    ),
     _CoverQuote(
      text:
          'If it scares you, it might be a good thing to try.',
      author: 'Seth Godin',
    ),
     _CoverQuote(
      text:
          'Start where you are. Use what you have. Do what you can.',
      author: 'Arthur Ashe',
    ),
     _CoverQuote(
      text:
          'The best time to plant a tree was 20 years ago. The second best time is now.',
      author: 'Chinese Proverb',
    ),
     _CoverQuote(
      text:
          'Only those who will risk going too far can possibly find out how far one can go.',
      author: 'T.S. Eliot',
    ),      
     _CoverQuote(
      text:
          'Opportunities multiply as they are seized.',
      author: 'Sun Tzu',
    ),
     _CoverQuote(
      text:
          'The only impossible journey is the one you never begin.',
      author: 'Tony Robbins',
    ),
     _CoverQuote(
      text:
          'The impulse to travel is one of the hopeful symptoms of life.',
      author: 'Agnes Repplier',
    ),
     _CoverQuote(
      text:
          'Once you have traveled, the voyage never ends.',
      author: 'Pat Conroy',
    ),
     _CoverQuote(
      text:
          'Travel and change of place impart new vigor to the mind.',
      author: 'Seneca',
    ),
     _CoverQuote(
      text:
          'A mind that is stretched by a new experience can never go back to its old dimensions.',
      author: 'Oliver Wendell Holmes Sr.',
    ),
     _CoverQuote(
      text:
          'People don’t take trips; trips take people.',
      author: 'John Steinbeck',
    ),
     _CoverQuote(
      text:
          'It is good to have an end to journey toward; but it is the journey that matters, in the end.',
      author: 'Ursula K. Le Guin',
    ),
     _CoverQuote(
      text:
          'The more I traveled, the more I realized fear makes strangers of people who should be friends.',
      author: 'Shirley MacLaine',
    ),
     _CoverQuote(
      text:
          'Wherever you go becomes a part of you somehow.',
      author: 'Anita Desai',
    ),
     _CoverQuote(
      text:
          'Exploration is wired into our brains. If we can see the horizon, we want to know what’s beyond.',
      author: 'Buzz Aldrin',
    ),
     _CoverQuote(
      text:'Adventure is allowing the unexpected to happen to you.',
      author: 'Richard Aldington',
    ),
     _CoverQuote(
      text:'We are all travelers in the wilderness of this world.',
      author: 'Robert Louis Stevenson',
    ),
    _CoverQuote(
      text:'The journey itself is my home.',
      author: 'Matsuo Bashō',
    ),
    _CoverQuote(
      text:'Surely, of all the wonders of the world, the horizon is the greatest.',
      author: 'Freya Stark',
    ),
    _CoverQuote(
      text:'If happiness is the goal—and it should be—then adventures should be top priority.',
      author: 'Richard Branson',
    ),
    _CoverQuote(
      text:'There’s a whole world out there, right outside your window. You’d be a fool to miss it.',
      author: 'Charlotte Eriksson',
    ),
    _CoverQuote(
      text:'Once the travel bug bites, there is no known antidote.',
      author: 'Michael Palin',
    ),
    _CoverQuote(
      text:'Travel makes a wise man better, and a fool worse.',
      author: 'Thomas Fuller',
    ),
    _CoverQuote(
      text:'Exploration is curiosity put into action.',
      author: 'Don Walsh',
    ),
    _CoverQuote(
      text:'I took a walk in the woods and came out taller than the trees',
      author: 'Henry David Thoreau',
    ),
    _CoverQuote(
      text:'Travel brings power and love back into your life.',
      author: 'Rumi',
    ),
    _CoverQuote(
      text:'One’s destination is never a place, but a new way of seeing things.',
      author: 'Henry Miller',
    ),
    _CoverQuote(
      text:'We travel, initially, to lose ourselves; and we travel, next, to find ourselves.',
      author: 'Pico Iyer',
    ),
    _CoverQuote(
      text:'To my mind, the greatest reward and luxury of travel is to be able to experience everyday things as if for the first time.',
      author: 'Bill Bryson',
    ),
    _CoverQuote(
      text:'The world is big and I want to have a good look at it before it gets dark.',
      author: 'John Muir',
    ),
    _CoverQuote(
      text:'We wander for distraction, but we travel for fulfillment.',
      author: 'Hilaire Belloc',
    ),
    _CoverQuote(
      text:'The greatest adventure is what lies ahead.',
      author: 'J.R.R. Tolkien',
    ),
    _CoverQuote(
      text:'Exploration is the engine that drives innovation.',
      author: 'Edith Widder',
    ),
    _CoverQuote(
      text:'Between every two pine trees there is a door leading to a new way of life.',
      author: 'John Muir',
    ),
    _CoverQuote(
      text:'The best education I have ever received was through travel.',
      author: 'Lisa Ling',
    ),
    _CoverQuote(
      text:'The purpose of life is to live it, to taste experience to the utmost.',
      author: 'Eleanor Roosevelt',
    ),
    _CoverQuote(
      text:'Experience is the teacher of all things.',
      author: 'Julius Caesar',
    ),
    _CoverQuote(
      text:'Experience is not what happens to you; it’s what you do with what happens to you.',
      author: 'Aldous Huxley',
    ),
    _CoverQuote(
      text:'Without new experiences, something inside us sleeps. The sleeper must awaken.',
      author: 'Frank Herbert',
    ),
    _CoverQuote(
      text:'The most difficult thing is the decision to act; the rest is merely tenacity.',
      author: 'Amelia Earhart',
    ),
    _CoverQuote(
      text:'Try new things and don’t be afraid to fail; it’s how you grow.',
      author: 'Indra Nooyi',
    ),
    _CoverQuote(
      text:'Live as if you were to die tomorrow. Learn as if you were to live forever.',
      author: 'Mahatma Gandhi',
    ),
    _CoverQuote(
      text:'Stuff your eyes with wonder.',
      author: 'Ray Bradbury',
    ),
    _CoverQuote(
      text:'Jobs fill your pockets, adventures fill your soul.',
      author: 'Jaime Lyn Beatty',
    ),
    _CoverQuote(
      text:'Not I, nor anyone else can travel that road for you. You must travel it by yourself.',
      author: 'Walt Whitman',
    ),
    _CoverQuote(
      text:'Travel changes you.',
      author: 'Anthony Bourdain',
    ),
    _CoverQuote(
      text:'Tell me, what is it you plan to do with your one wild and precious life?',
      author: 'Mary Oliver',
    ),
    _CoverQuote(
      text:'The discovery of a new dish does more for the happiness of mankind than the discovery of a star.',
      author: 'Jean Anthelme Brillat-Savarin',
    ),
    _CoverQuote(
      text:'One cannot think well, love well, sleep well, if one has not dined well.”',
      author: 'Virginia Woolf',
    ),
    _CoverQuote(
      text:'Move, as far as you can—across the ocean or simply across town—and eat interesting food.',
      author: 'Anthony Bourdain',
    ),
    _CoverQuote(
      text:'Pull up a chair. Take a taste. Come join us. Life is so endlessly delicious.',
      author: 'Ruth Reichl',
    ),
    _CoverQuote(
      text:'Variety’s the very spice of life.',
      author: 'William Cowper',
    ),
    _CoverQuote(
      text:'If more of us valued food and cheer and song above hoarded gold, it would be a merrier world.',
      author: 'J.R.R. Tolkien',
    ),
    _CoverQuote(
      text:'Everywhere is within walking distance if you have the time.',
      author: 'Steven Wright',
    ),
    _CoverQuote(
      text:'Every exit is an entrance somewhere else.',
      author: 'Tom Stoppard',
    ),
    _CoverQuote(
      text:'A city is a language, a reservoir of possibilities.',
      author: 'Rebecca Solnit',
    ),
    // _CoverQuote(
    //   text:'',
    //   author: '',
    // ),
  ];
  Future<void>? _coverBackgroundsFuture;
  List<Reference> _coverBackgroundRefs = [];
  String? _coverBackgroundUrl;
  bool _isCoverImageLoaded = false;
  _CoverQuote? _currentCoverQuote;

  @override
  bool get wantKeepAlive =>
      false; // Changed to false so cover page shows every time

  @override
  void initState() {
    super.initState();
    _currentCoverQuote = _pickRandomCoverQuote();
    _prepareCoverBackgrounds();
    _initializeFeed();
    final String? initialToken = widget.initialShareToken;
    if (initialToken != null && initialToken.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showSharedPreview(initialToken);
      });
    }
  }

  void _setHasStartedDiscovering(bool value) {
    if (mounted) {
      setState(() {
        _hasStartedDiscovering = value;
        if (!value) {
          _currentCoverQuote = _pickRandomCoverQuote();
          _isCoverImageLoaded = false; // Reset cover image loaded state when returning to cover
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DiscoveryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? newToken = widget.initialShareToken;
    if (newToken != null &&
        newToken.isNotEmpty &&
        newToken != oldWidget.initialShareToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showSharedPreview(newToken);
      });
    }
  }

  Future<void> refreshFeed() async {
    if (!mounted) return;
    setState(() {
      _publicExperiences.clear();
      _feedItems.clear();
      _mapsPreviewFutures.clear();
      _usedMediaKeys.clear();
      _userSavedPlaceIds.clear();
      _userSavedMediaUrls.clear();
      _userPlacesLoadFuture = null; // Force reload of user saved places
      _lastDocument = null;
      _hasMore = true;
      _isFetchingExperiences = false;
      _isLoading = true;
      _isError = false;
      _isPreparingMore = false;
      _errorMessage = null;
      _currentPage = 0;
      _dragDistance = 0;
      _currentCoverQuote = _pickRandomCoverQuote();
      _isCoverImageLoaded = false; // Reset cover image loaded state
    });
    await _initializeFeed();
  }

  Future<void> showSharedPreview(String token) async {
    if (!mounted || token.isEmpty) return;
    if (_isLoadingSharedPreview) {
      return;
    }
    if (_lastDisplayedShareToken == token &&
        _pageController.hasClients &&
        _feedItems.isNotEmpty) {
      _maybeAnimateToPage(0);
      return;
    }

    setState(() {
      _isLoadingSharedPreview = true;
    });

    try {
      final DiscoverySharePayload payload =
          await _discoveryShareService.fetchShare(token);
      if (!mounted) return;
      await _integrateSharedPayload(payload);
      _lastDisplayedShareToken = token;
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to load shared preview ($token): $e');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open the shared discovery preview. Please try again.',
          ),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingSharedPreview = false;
      });
    }
  }

  Future<void> _initializeFeed() async {
    try {
      // Start loading user's saved data in parallel with initial fetch
      final userDataFuture = Future.wait([
        _ensureSeenMediaLoaded(),
        _ensureUserSavedPlacesLoaded(),
      ]);

      // Wait for user data to complete before fetching experiences
      await userDataFuture;

      // Quick initial fetch: just get enough for first 10 previews (~20-30 experiences)
      // This reduces wait time significantly
      await _fetchMoreExperiencesIfNeeded(force: true, quickStart: true);

      // Generate initial batch of 5 items
      await _generateFeedItems(count: 5);

      // Mark the first item as seen since it will be displayed
      if (_feedItems.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _feedItems.isNotEmpty) {
            _recordFeedItemsAsSeen([_feedItems[0]]);
          }
        });
      }

      // Continue loading more experiences in the background to reach target pool size
      if (mounted) {
        _continueBackgroundLoading();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _errorMessage = 'Unable to load discovery feed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _continueBackgroundLoading() async {
    // Continue fetching in background without blocking UI
    try {
      await _fetchMoreExperiencesIfNeeded(force: true, quickStart: false);
    } catch (e) {
      debugPrint('DiscoveryScreen: Background loading failed: $e');
      // Don't show error to user, just log it
    }
  }

  Future<void> _fetchMoreExperiencesIfNeeded({
    bool force = false,
    bool quickStart = false,
  }) async {
    if (!force && (_isFetchingExperiences || !_hasMore)) {
      return;
    }

    // Target pool size: smaller for quick start, larger for background loading
    final int targetPoolSize = quickStart ? 30 : 100;
    if (!force && _publicExperiences.length >= targetPoolSize) {
      return;
    }

    _isFetchingExperiences = true;
    int totalFetched = 0;
    int totalFiltered = 0;
    int totalEligible = 0;

    try {
      // Keep paging until we have enough eligible experiences or run out
      while (_publicExperiences.length < targetPoolSize && _hasMore) {
        final page = await _experienceService.fetchPublicExperiencesPage(
          startAfter: _lastDocument,
          limit: 50,
        );

        _lastDocument = page.lastDocument;
        _hasMore = page.hasMore;
        totalFetched += page.experiences.length;

        if (page.experiences.isNotEmpty) {
          // Filter: must have media AND user must not have this place saved
          // AND must have at least one unsaved media URL
          final eligibleExperiences = page.experiences.where((exp) {
            // Must have media
            if (exp.allMediaPaths.isEmpty) return false;

            // Must not be a place the user already has saved
            final placeId = exp.location.placeId;
            if (placeId != null && placeId.isNotEmpty) {
              if (_userSavedPlaceIds.contains(placeId)) {
                totalFiltered++;
                return false;
              }
            }

            // Must have at least ONE media URL that the user hasn't saved
            bool hasUnsavedMedia = false;
            for (final mediaUrl in exp.allMediaPaths) {
              final normalizedUrl = _normalizeUrlForComparison(mediaUrl);
              if (normalizedUrl.isNotEmpty &&
                  !_userSavedMediaUrls.contains(normalizedUrl)) {
                hasUnsavedMedia = true;
                break;
              }
            }

            if (!hasUnsavedMedia) {
              totalFiltered++;
              return false;
            }

            return true;
          }).toList();

          if (eligibleExperiences.isNotEmpty) {
            _publicExperiences.addAll(eligibleExperiences);
            totalEligible += eligibleExperiences.length;
          }
        }

        // If we've run out of pages, stop
        if (!_hasMore) break;
      }

      final loadType = quickStart ? 'Quick start' : 'Background load';
      debugPrint(
          'DiscoveryScreen: $loadType paging complete. Fetched $totalFetched experiences, filtered $totalFiltered (user has saved), added $totalEligible eligible. Total pool: ${_publicExperiences.length}. HasMore: $_hasMore');
    } finally {
      _isFetchingExperiences = false;
    }
  }

  Future<void> _ensureSeenMediaLoaded() {
    return _seenMediaLoadFuture ??= _loadSeenMediaKeys();
  }

  Future<void> _loadSeenMediaKeys() async {
    try {
      final prefs = await _getSharedPreferences();
      final storedKeys = prefs.getStringList(_seenMediaPrefsKey);
      _persistedSeenMediaKeys
        ..clear()
        ..addAll(storedKeys ?? const <String>[]);
      debugPrint(
          'DiscoveryScreen: Loaded ${_persistedSeenMediaKeys.length} seen media keys from storage');
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to load seen media keys: $e');
      _persistedSeenMediaKeys.clear();
    }
  }

  Future<SharedPreferences> _getSharedPreferences() async {
    if (_sharedPreferences != null) {
      return _sharedPreferences!;
    }
    final prefs = await SharedPreferences.getInstance();
    _sharedPreferences = prefs;
    return prefs;
  }

  Future<void> _persistSeenMediaKeys() async {
    try {
      final prefs = await _getSharedPreferences();
      await prefs.setStringList(
        _seenMediaPrefsKey,
        _persistedSeenMediaKeys.toList(),
      );
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to persist seen media keys: $e');
    }
  }

  Future<void> _resetPersistedSeenMediaKeys() async {
    _persistedSeenMediaKeys.clear();
    try {
      final prefs = await _getSharedPreferences();
      await prefs.remove(_seenMediaPrefsKey);
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to reset seen media keys: $e');
    }
  }

  Future<void> _ensureUserSavedPlacesLoaded() {
    return _userPlacesLoadFuture ??= _loadUserSavedPlaces();
  }

  Future<void> _loadUserSavedPlaces() async {
    try {
      // Get current user ID
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        debugPrint(
            'DiscoveryScreen: No authenticated user, skipping saved places load');
        return;
      }

      final prefs = await _getSharedPreferences();

      // Try to load from cache first
      final cachedPlaces = prefs.getStringList(_savedPlacesPrefsKey);
      final cachedMedia = prefs.getStringList(_savedMediaPrefsKey);
      final cacheTimestamp = prefs.getInt('${_savedPlacesPrefsKey}_timestamp');

      final now = DateTime.now().millisecondsSinceEpoch;
      final cacheAge = cacheTimestamp != null
          ? Duration(milliseconds: now - cacheTimestamp)
          : null;

      // Use cache if it's valid (less than 6 hours old)
      if (cachedPlaces != null &&
          cachedMedia != null &&
          cacheAge != null &&
          cacheAge < _cacheValidDuration) {
        _userSavedPlaceIds.addAll(cachedPlaces);
        _userSavedMediaUrls.addAll(cachedMedia);
        debugPrint(
            'DiscoveryScreen: Loaded ${_userSavedPlaceIds.length} place IDs and ${_userSavedMediaUrls.length} media URLs from cache (age: ${cacheAge.inMinutes}min)');

        // Refresh cache in background without blocking
        _refreshUserSavedPlacesInBackground(userId, prefs);
        return;
      }

      // No valid cache - load from Firestore
      debugPrint('DiscoveryScreen: No valid cache, loading from Firestore...');
      await _fetchAndCacheUserSavedPlaces(userId, prefs);
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to load user saved places: $e');
      _userSavedPlaceIds.clear();
      _userSavedMediaUrls.clear();
    }
  }

  Future<void> _fetchAndCacheUserSavedPlaces(
      String userId, SharedPreferences prefs) async {
    // Fetch all user's experiences to get their saved place IDs and media URLs
    final experiences = await _experienceService.getExperiencesByUser(
      userId,
      limit: 10000, // High limit to get all experiences
    );

    _userSavedPlaceIds.clear();
    _userSavedMediaUrls.clear();

    // Collect all place IDs and media URLs from experiences
    for (final experience in experiences) {
      // Place IDs
      final placeId = experience.location.placeId;
      if (placeId != null && placeId.isNotEmpty) {
        _userSavedPlaceIds.add(placeId);
      }

      // Image URLs (direct image links)
      for (final imageUrl in experience.imageUrls) {
        if (imageUrl.isNotEmpty) {
          _userSavedMediaUrls.add(_normalizeUrlForComparison(imageUrl));
        }
      }
    }

    // Also collect media URLs from SharedMediaItems where the user has saved them
    // Query for SharedMediaItems that contain any of the user's experience IDs
    final experienceIds =
        experiences.map((e) => e.id).where((id) => id.isNotEmpty).toList();

    if (experienceIds.isNotEmpty) {
      // Fetch shared media items in batches (Firestore 'array-contains-any' limit is 10)
      const int batchSize = 10;
      for (int i = 0; i < experienceIds.length; i += batchSize) {
        final batch = experienceIds.skip(i).take(batchSize).toList();
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('sharedMediaItems')
              .where('experienceIds', arrayContainsAny: batch)
              .get();

          for (final doc in snapshot.docs) {
            try {
              final mediaItem = SharedMediaItem.fromFirestore(doc);
              final path = mediaItem.path;
              if (path.isNotEmpty) {
                _userSavedMediaUrls.add(_normalizeUrlForComparison(path));
              }
            } catch (e) {
              debugPrint(
                  'DiscoveryScreen: Failed to parse SharedMediaItem ${doc.id}: $e');
            }
          }
        } catch (e) {
          debugPrint(
              'DiscoveryScreen: Failed to fetch SharedMediaItems batch: $e');
        }
      }
    }

    debugPrint(
        'DiscoveryScreen: Loaded ${_userSavedPlaceIds.length} saved place IDs and ${_userSavedMediaUrls.length} saved media URLs from Firestore');

    // Cache the results
    try {
      await prefs.setStringList(
          _savedPlacesPrefsKey, _userSavedPlaceIds.toList());
      await prefs.setStringList(
          _savedMediaPrefsKey, _userSavedMediaUrls.toList());
      await prefs.setInt('${_savedPlacesPrefsKey}_timestamp',
          DateTime.now().millisecondsSinceEpoch);
      debugPrint('DiscoveryScreen: Cached user saved places and media');
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to cache user saved places: $e');
    }
  }

  void _refreshUserSavedPlacesInBackground(
      String userId, SharedPreferences prefs) {
    // Refresh in background without blocking or showing errors
    Future.microtask(() async {
      try {
        await _fetchAndCacheUserSavedPlaces(userId, prefs);
        debugPrint(
            'DiscoveryScreen: Background refresh of saved places complete');
      } catch (e) {
        debugPrint('DiscoveryScreen: Background refresh failed: $e');
      }
    });
  }

  Future<void> _integrateSharedPayload(DiscoverySharePayload payload) async {
    await _ensureSeenMediaLoaded();
    final PublicExperience experience = payload.experience;
    final String mediaUrl = payload.mediaUrl;
    if (mediaUrl.isEmpty) return;

    // Skip unsupported preview types like Yelp for the discovery feed
    if (_classifyUrl(mediaUrl) == _MediaType.yelp) {
      debugPrint(
          'DiscoveryScreen: Skipping shared payload because Yelp previews are not supported.');
      return;
    }

    final _DiscoveryFeedItem newItem = _DiscoveryFeedItem(
      experience: experience,
      mediaUrl: mediaUrl,
    );

    setState(() {
      _feedItems.removeWhere(
        (item) =>
            item.experience.id == experience.id && item.mediaUrl == mediaUrl,
      );
      _feedItems.insert(0, newItem);
      _currentPage = 0;
    });

    await _maybeCheckIfMediaSaved(newItem);
    await _recordFeedItemsAsSeen([newItem]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients &&
          _pageController.position.hasPixels &&
          _pageController.position.haveDimensions) {
        _pageController.jumpToPage(0);
      }
    });
  }

  Future<void> _generateFeedItems({int count = 5}) async {
    if (count <= 0) return;

    await _ensureSeenMediaLoaded();

    final List<_DiscoveryFeedItem> newItems = [];
    final int maxAttempts = count * 50;
    int attempts = 0;
    int skippedFiltered = 0;
    int skippedSeen = 0;

    debugPrint(
        'DiscoveryScreen: Generating $count feed items. Pool: ${_publicExperiences.length} experiences, Seen: ${_persistedSeenMediaKeys.length} media');

    while (newItems.length < count && attempts < maxAttempts) {
      attempts++;

      if (_publicExperiences.isEmpty) {
        if (_hasMore) {
          await _fetchMoreExperiencesIfNeeded(force: true);
          continue;
        } else {
          break;
        }
      }

      final experience =
          _publicExperiences[_random.nextInt(_publicExperiences.length)];

      if (experience.allMediaPaths.isEmpty) {
        continue;
      }

      final mediaUrl = experience
          .allMediaPaths[_random.nextInt(experience.allMediaPaths.length)];

      if (mediaUrl.isEmpty) {
        continue;
      }

      // Skip Yelp, Google Maps, and generic URL previews
      final mediaType = _classifyUrl(mediaUrl);
      if (mediaType == _MediaType.yelp ||
          mediaType == _MediaType.maps ||
          mediaType == _MediaType.generic) {
        skippedFiltered++;
        continue;
      }

      final totalCombos = _calculateTotalAvailableMediaPaths();
      if (totalCombos > 0) {
        if (_persistedSeenMediaKeys.length >= totalCombos) {
          debugPrint('DiscoveryScreen: All media seen! Resetting seen keys.');
          await _resetPersistedSeenMediaKeys();
        }
        if (_usedMediaKeys.length >= totalCombos) {
          _usedMediaKeys.clear();
        }
      }

      final key = _mediaKey(experience, mediaUrl);
      if (_persistedSeenMediaKeys.contains(key)) {
        skippedSeen++;
        if (_hasMore && attempts % 20 == 0) {
          await _fetchMoreExperiencesIfNeeded(force: true);
        }
        continue;
      }
      if (_usedMediaKeys.contains(key)) {
        if (_hasMore && attempts % 20 == 0) {
          await _fetchMoreExperiencesIfNeeded(force: true);
        }
        continue;
      }

      // No need to check "already saved" here - we already filtered out
      // experiences at places the user has saved during the paging step
      _usedMediaKeys.add(key);
      newItems.add(
        _DiscoveryFeedItem(
          experience: experience,
          mediaUrl: mediaUrl,
        ),
      );
    }

    debugPrint(
        'DiscoveryScreen: Feed generation complete. Generated: ${newItems.length}/$count items in $attempts attempts. Skipped - Seen: $skippedSeen, Filtered: $skippedFiltered');

    if (newItems.isNotEmpty) {
      if (mounted) {
        setState(() {
          _feedItems.addAll(newItems);
        });
      }
      // Note: Items are now marked as seen when viewed, not when generated
    }
  }

  String _mediaKey(PublicExperience experience, String mediaUrl) {
    final String fallbackId = experience.placeID.isNotEmpty
        ? experience.placeID
        : experience.name.trim().toLowerCase();
    final String idPart = experience.id.isNotEmpty ? experience.id : fallbackId;
    return '$idPart::$mediaUrl';
  }

  int _calculateTotalAvailableMediaPaths() {
    return _publicExperiences.fold<int>(
      0,
      (runningTotal, experience) =>
          runningTotal + experience.allMediaPaths.length,
    );
  }

  Future<void> _recordFeedItemsAsSeen(List<_DiscoveryFeedItem> items) async {
    if (items.isEmpty) return;
    await _ensureSeenMediaLoaded();
    bool didUpdate = false;
    for (final item in items) {
      final key = _mediaKey(item.experience, item.mediaUrl);
      if (_persistedSeenMediaKeys.add(key)) {
        didUpdate = true;
      }
    }
    if (didUpdate) {
      await _persistSeenMediaKeys();
      debugPrint(
          'DiscoveryScreen: Marked ${items.length} item(s) as seen. Total seen: ${_persistedSeenMediaKeys.length}');
    }
  }

  void _handlePageChanged(int index) {
    setState(() {
      _currentPage = index;
    });

    // Mark the viewed item as seen
    if (index >= 0 && index < _feedItems.length) {
      final item = _feedItems[index];
      _recordFeedItemsAsSeen([item]);
    }

    if (_feedItems.length - index <= 2) {
      _prepareMoreItems();
    }
  }

  Future<void> _prepareMoreItems() async {
    if (_isPreparingMore) return;
    _isPreparingMore = true;

    try {
      if (_hasMore) {
        await _fetchMoreExperiencesIfNeeded();
      }
      await _generateFeedItems(count: 3);
    } catch (_) {
      // Intentionally swallow errors for background prefetching.
    } finally {
      _isPreparingMore = false;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _isError = false;
      _errorMessage = null;
      _isLoading = true;
      _publicExperiences.clear();
      _feedItems.clear();
      _usedMediaKeys.clear();
      _lastDocument = null;
      _hasMore = true;
      _currentPage = 0;
      _dragDistance = 0;
    });

    await _initializeFeed();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('DiscoveryScreen: failed to launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Show cover page immediately if user hasn't started discovering yet
    // (loading happens in background)
    if (!_hasStartedDiscovering) {
      return _buildCoverPage();
    }

    // Only show loading/error states if user has started discovering
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_isError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage ??
                    'Something went wrong while loading the discovery feed.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_feedItems.isEmpty) {
      return const Center(
        child: Text(
          'No public experiences to show yet.\nCheck back soon for new recommendations.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    final feedContent = GestureDetector(
      onVerticalDragStart: (_) {
        _dragDistance = 0;
      },
      onVerticalDragUpdate: (details) {
        final delta = details.primaryDelta ?? 0;
        _dragDistance += delta;
        if (!_pageController.hasClients ||
            !_pageController.position.hasPixels ||
            !_pageController.position.haveDimensions) {
          return;
        }
        final position = _pageController.position;
        final double newOffset = (position.pixels - delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        _pageController.jumpTo(newOffset);
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final int targetPage = _resolveTargetPageForDragEnd(velocity);
        _maybeAnimateToPage(targetPage);
        _resetDragTracking();
      },
      onVerticalDragCancel: () {
        _maybeAnimateToPage(_currentPage);
        _resetDragTracking();
      },
      child: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.vertical,
        itemCount: _feedItems.length,
        onPageChanged: _handlePageChanged,
        itemBuilder: (context, index) {
          final item = _feedItems[index];
          return _buildFeedPage(item);
        },
      ),
    );

    if (!_isLoadingSharedPreview) {
      return feedContent;
    }

    return Stack(
      children: [
        feedContent,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _maybeAnimateToPage(int targetPage) {
    if (targetPage < 0 || targetPage >= _feedItems.length) {
      return;
    }
    if (!_pageController.hasClients ||
        !_pageController.position.hasPixels ||
        !_pageController.position.haveDimensions) {
      return;
    }
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  int _resolveTargetPageForDragEnd(double velocity) {
    if (_feedItems.isEmpty) {
      return 0;
    }
    if (velocity < -300 || _dragDistance <= -_dragThreshold) {
      return min(_currentPage + 1, _feedItems.length - 1);
    }
    if (velocity > 300 || _dragDistance >= _dragThreshold) {
      return max(_currentPage - 1, 0);
    }
    return _currentPage;
  }

  void _resetDragTracking() {
    _dragDistance = 0;
  }

  _CoverQuote? _pickRandomCoverQuote() {
    if (_coverQuotes.isEmpty) {
      return null;
    }
    return _coverQuotes[_random.nextInt(_coverQuotes.length)];
  }

  void _prepareCoverBackgrounds() {
    _coverBackgroundsFuture ??= _fetchCoverBackgrounds();
  }

  Future<void> _fetchCoverBackgrounds() async {
    try {
      final ListResult result =
          await FirebaseStorage.instance.ref(_coverBackgroundFolder).listAll();
      if (result.items.isEmpty) {
        debugPrint(
          'DiscoveryScreen: No cover background assets found at $_coverBackgroundFolder',
        );
        return;
      }
      _coverBackgroundRefs = result.items;
      await _selectRandomCoverBackground();
      
      // Pre-fetch additional cover backgrounds in the background for faster switching
      _prefetchAdditionalCoverBackgrounds();
    } catch (e, stackTrace) {
      debugPrint(
        'DiscoveryScreen: Failed to load cover backgrounds: $e\n$stackTrace',
      );
    }
  }
  
  void _prefetchAdditionalCoverBackgrounds() {
    // Pre-fetch up to 2 additional random cover backgrounds in the background
    Future.microtask(() async {
      if (!mounted || _coverBackgroundRefs.length < 2) return;
      
      final indicesToPrefetch = <int>{};
      while (indicesToPrefetch.length < 2 && indicesToPrefetch.length < _coverBackgroundRefs.length) {
        indicesToPrefetch.add(_random.nextInt(_coverBackgroundRefs.length));
      }
      
      for (final index in indicesToPrefetch) {
        if (!mounted) break;
        try {
          final url = await _coverBackgroundRefs[index].getDownloadURL();
          if (!mounted) break;
          await precacheImage(NetworkImage(url), context);
          debugPrint('DiscoveryScreen: Pre-fetched cover background ${index + 1}/${_coverBackgroundRefs.length}');
        } catch (e) {
          debugPrint('DiscoveryScreen: Failed to pre-fetch cover background: $e');
        }
      }
    });
  }

  Future<void> _selectRandomCoverBackground() async {
    if (_coverBackgroundRefs.isEmpty) {
      return;
    }
    final Reference reference =
        _coverBackgroundRefs[_random.nextInt(_coverBackgroundRefs.length)];
    try {
      final String url = await reference.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _coverBackgroundUrl = url;
        _isCoverImageLoaded = false; // Reset loaded state for new image
      });
      // Precache immediately (non-blocking) to speed up subsequent loads and animations
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        precacheImage(NetworkImage(url), context).catchError((e) {
          debugPrint('DiscoveryScreen: Failed to precache image: $e');
        });
      });
    } catch (e) {
      debugPrint(
        'DiscoveryScreen: Failed to fetch cover background URL: $e',
      );
    }
  }

  Widget _buildCoverPage() {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final LinearGradient fallbackGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.black,
        Colors.grey.shade900,
        Colors.black,
      ],
    );

    final Widget background = Container(
      decoration: BoxDecoration(gradient: fallbackGradient),
    );

    final Widget? coverImage = _coverBackgroundUrl == null
        ? null
        : Image.network(
            _coverBackgroundUrl!,
            key: ValueKey(_coverBackgroundUrl),
            fit: BoxFit.cover,
            color: Colors.black.withOpacity(0.45),
            colorBlendMode: BlendMode.darken,
            frameBuilder: (BuildContext context, Widget child, int? frame,
                bool wasSynchronouslyLoaded) {
              // Mark image as loaded when frame is available
              if (frame != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_isCoverImageLoaded) {
                    setState(() {
                      _isCoverImageLoaded = true;
                    });
                  }
                });
              }
              if (wasSynchronouslyLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_isCoverImageLoaded) {
                    setState(() {
                      _isCoverImageLoaded = true;
                    });
                  }
                });
                return child;
              }
              return AnimatedOpacity(
                opacity: frame == null ? 0.0 : 1.0,
                duration: _coverFadeDuration,
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        if (coverImage != null) coverImage,
        // Show app icon in top 40% while waiting for cover image to load
        if (!_isCoverImageLoaded)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.4,
            child: Center(
              child: Image.asset(
                'assets/icon/icon.png',
                fit: BoxFit.contain,
                width: 450,
                height: 450,
              ),
            ),
          ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, right: 16),
              child: Tooltip(
                message: 'View Map',
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: _isCoverImageLoaded
                      ? Image.asset(
                          'assets/icon/icon-cropped.png',
                          width: 28,
                          height: 28,
                        )
                      : const Icon(
                          Icons.map_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                  label: const Text(
                    'Map',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const MapScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_currentCoverQuote != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentCoverQuote!.text,
                            style: GoogleFonts.playfairDisplay(
                              color: Colors.white,
                              fontSize: 24,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_currentCoverQuote!.author != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              '— ${_currentCoverQuote!.author!}',
                              style: GoogleFonts.playfairDisplay(
                                color: Colors.white70,
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                  const Text(
                    'Explore amazing experiences\nshared by the community',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton(
                    onPressed: () => _setHasStartedDiscovering(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 8,
                    ),
                    child: const Text(
                      'Start Discovering',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedPage(_DiscoveryFeedItem item) {
    final preview = _buildPreviewForItem(item);
    _maybeCheckIfMediaSaved(item);

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        preview,
        IgnorePointer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black87,
                  Colors.transparent,
                ],
                stops: [0.0, 0.6],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 96,
          bottom: 32,
          child: _buildMetadata(item),
        ),
        Positioned(
          right: 16,
          bottom: 32,
          child: _buildActionButtons(item),
        ),
      ],
    );
  }

  Widget _buildMetadata(_DiscoveryFeedItem item) {
    final PublicExperience experience = item.experience;
    final location = experience.location;
    final details = <String>[];

    if ((location.city ?? '').trim().isNotEmpty) {
      details.add(location.city!.trim());
    }
    if ((location.state ?? '').trim().isNotEmpty) {
      details.add(location.state!.trim());
    }

    final subtitle = details.join(', ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleExperienceTap(experience),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  experience.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FutureBuilder<List<Experience>>(
                future: _getLinkedExperiencesForMedia(item.mediaUrl),
                builder: (context, snapshot) {
                  final experiences = snapshot.data;
                  if (experiences == null || experiences.length <= 1) {
                    return const SizedBox.shrink();
                  }
                  return TextButton(
                    onPressed: () => _showLinkedExperiencesDialog(item),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'and more',
                      style: TextStyle(fontSize: 13),
                    ),
                  );
                },
              ),
            ],
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(_DiscoveryFeedItem item) {
    final sourceButton = _buildSourceActionButton(item);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (sourceButton != null) ...[
          sourceButton,
          const SizedBox(height: 16),
        ],
        ValueListenableBuilder<bool?>(
          valueListenable: item.isMediaAlreadySaved,
          builder: (context, isSaved, _) {
            final bool resolvedSaved = isSaved ?? false;
            return _buildActionButton(
              icon: resolvedSaved ? Icons.bookmark : Icons.bookmark_border,
              label: resolvedSaved ? 'Saved' : 'Save',
              onPressed:
                  resolvedSaved ? null : () => _handleBookmarkTapped(item),
            );
          },
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.place_outlined,
          label: 'Location',
          onPressed: () {
            final location = item.experience.location;
            final locationForMap = (location.displayName != null &&
                    location.displayName!.trim().isNotEmpty)
                ? location
                : location.copyWith(displayName: item.experience.name);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MapScreen(
                  initialExperienceLocation: locationForMap,
                  initialPublicExperience: item.experience,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.ios_share,
          label: 'Share',
          onPressed: _isShareInProgress ? null : () => _handleShareTapped(item),
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.more_vert,
          label: 'More',
          onPressed: () => _showMoreOptions(item),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    Color? backgroundColor,
    VoidCallback? onPressed,
  }) {
    assert(icon != null || iconWidget != null,
        '_buildActionButton requires either an IconData or a Widget.');
    final Widget iconContent =
        iconWidget ?? Icon(icon, color: Colors.white, size: 28);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.black45,
            borderRadius: BorderRadius.circular(24),
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: iconContent,
            iconSize: iconWidget == null ? 28 : 24,
            splashRadius: 28,
            color: Colors.white,
            disabledColor: Colors.white70,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _showMoreOptions(_DiscoveryFeedItem item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showReportDialog(item);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReportDialog(_DiscoveryFeedItem item) {
    String? selectedReason;
    final TextEditingController explanationController = TextEditingController();
    bool isSubmitting = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'What would you like to report about this content?',
                style: TextStyle(fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioListTile<String>(
                      title: const Text('Inappropriate content'),
                      value: 'inappropriate',
                      groupValue: selectedReason,
                      onChanged: isSubmitting
                          ? null
                          : (value) {
                              setState(() {
                                selectedReason = value;
                              });
                            },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<String>(
                      title: const Text('Incorrect Information'),
                      value: 'incorrect',
                      groupValue: selectedReason,
                      onChanged: isSubmitting
                          ? null
                          : (value) {
                              setState(() {
                                selectedReason = value;
                              });
                            },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<String>(
                      title: const Text('Other'),
                      value: 'other',
                      groupValue: selectedReason,
                      onChanged: isSubmitting
                          ? null
                          : (value) {
                              setState(() {
                                selectedReason = value;
                              });
                            },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Please explain:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: explanationController,
                      maxLines: 4,
                      enabled: !isSubmitting,
                      decoration: InputDecoration(
                        hintText: 'Provide additional details...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          explanationController.dispose();
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          await _handleReportSubmit(
                            dialogContext: dialogContext,
                            item: item,
                            selectedReason: selectedReason,
                            explanationController: explanationController,
                            setSubmitting: (value) {
                              setState(() {
                                isSubmitting = value;
                              });
                            },
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleReportSubmit({
    required BuildContext dialogContext,
    required _DiscoveryFeedItem item,
    required String? selectedReason,
    required TextEditingController explanationController,
    required void Function(bool) setSubmitting,
  }) async {
    // Validate that a reason is selected
    if (selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a reason for reporting'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Get current user
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to report content'),
        ),
      );
      return;
    }

    setSubmitting(true);

    try {
      // Check if user has already reported this content
      final existingReport = await _reportService.findExistingReport(
        userId: currentUser.uid,
        experienceId: item.experience.id,
        previewURL: item.mediaUrl,
      );

      if (existingReport != null) {
        if (!mounted) return;
        explanationController.dispose();
        Navigator.of(dialogContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You have already reported this content. Thank you for your feedback!',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Get device info
      final deviceInfo = _getDeviceInfo();

      // Create the Report object
      final report = Report(
        id: '', // Will be auto-generated by Firestore
        userId: currentUser.uid,
        screenReported: 'discovery_screen',
        previewURL: item.mediaUrl,
        experienceId: item.experience.id,
        reportType: selectedReason,
        details: explanationController.text.trim(),
        createdAt: DateTime.now(),
        reportedUserId: null, // Public experiences don't track original creator
        publicExperienceId: item.experience.id,
        deviceInfo: deviceInfo,
      );

      // Submit via service
      await _reportService.submitReport(report);

      if (!mounted) return;
      explanationController.dispose();
      Navigator.of(dialogContext).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Thank you for your feedback!'),
          duration: Duration(seconds: 3),
        ),
      );

      debugPrint(
          'DiscoveryScreen: Report submitted for experience ${item.experience.id}');
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to submit report: $e');
      if (!mounted) return;
      setSubmitting(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to submit report. Please try again.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  String _getDeviceInfo() {
    if (kIsWeb) {
      return 'Web';
    }
    try {
      if (Platform.isIOS) {
        return 'iOS';
      } else if (Platform.isAndroid) {
        return 'Android';
      } else if (Platform.isMacOS) {
        return 'macOS';
      } else if (Platform.isWindows) {
        return 'Windows';
      } else if (Platform.isLinux) {
        return 'Linux';
      }
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to get platform info: $e');
    }
    return 'Unknown';
  }

  Future<void> _openReadOnlyExperience(
      PublicExperience publicExperience) async {
    final Experience draft = _buildExperienceDraft(publicExperience);
    final List<SharedMediaItem> mediaItems =
        publicExperience.buildMediaItemsForPreview();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExperiencePageScreen(
          experience: draft,
          category: _publicReadOnlyCategory,
          userColorCategories: const <ColorCategory>[],
          initialMediaItems: mediaItems,
          readOnlyPreview: true,
          publicExperienceId: publicExperience.id,
        ),
      ),
    );
  }

  Future<void> _handleExperienceTap(PublicExperience publicExperience) async {
    Experience? editableExperience;
    final String? placeId = publicExperience.location.placeId;
    if (placeId != null && placeId.isNotEmpty) {
      editableExperience =
          await _experienceService.findEditableExperienceByPlaceId(placeId);
    }

    if (!mounted) return;

    if (editableExperience != null) {
      await _openEditableExperience(editableExperience);
    } else {
      await _openReadOnlyExperience(publicExperience);
    }
  }

  Future<void> _openEditableExperience(Experience experience) async {
    await _ensureUserCollectionsLoaded();
    final UserCategory category = _resolveCategoryForExperience(experience);
    final List<ColorCategory> colorCategories = _userColorCategories.isEmpty
        ? const <ColorCategory>[]
        : _userColorCategories;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExperiencePageScreen(
          experience: experience,
          category: category,
          userColorCategories: colorCategories,
        ),
      ),
    );
  }

  Future<void> _ensureUserCollectionsLoaded() {
    if (_userCollectionsFuture != null) {
      return _userCollectionsFuture!;
    }
    _userCollectionsFuture = _loadUserCollections().whenComplete(() {
      _userCollectionsFuture = null;
    });
    return _userCollectionsFuture!;
  }

  Future<void> _loadUserCollections() async {
    try {
      final categories = await _experienceService.getUserCategories(
        includeSharedEditable: true,
      );
      final colorCategories = await _experienceService.getUserColorCategories(
        includeSharedEditable: true,
      );
      _userCategories = categories;
      _userColorCategories = colorCategories;
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed to load user collections: $e');
    }
  }

  void _markMediaAsSaved(String mediaUrl) {
    final String normalizedKey = _normalizeUrlForComparison(mediaUrl);
    if (normalizedKey.isEmpty) return;
    // Add to user's saved media URLs so it won't show up again
    _userSavedMediaUrls.add(normalizedKey);

    // Invalidate cache so it refreshes next time
    _invalidateSavedPlacesCache();
  }

  void _invalidateSavedPlacesCache() {
    // Invalidate the cache in the background
    Future.microtask(() async {
      try {
        final prefs = await _getSharedPreferences();
        await prefs.remove('${_savedPlacesPrefsKey}_timestamp');
        debugPrint('DiscoveryScreen: Invalidated saved places cache');
      } catch (e) {
        debugPrint('DiscoveryScreen: Failed to invalidate cache: $e');
      }
    });
  }

  Future<void> _maybeCheckIfMediaSaved(_DiscoveryFeedItem item) async {
    if (item.isMediaAlreadySaved.value != null) {
      return;
    }
    try {
      // Check if this specific media URL has been saved by THIS user
      final normalizedUrl = _normalizeUrlForComparison(item.mediaUrl);
      item.isMediaAlreadySaved.value =
          _userSavedMediaUrls.contains(normalizedUrl);
    } catch (e) {
      debugPrint('DiscoveryScreen: Failed media check: $e');
      item.isMediaAlreadySaved.value = false;
    }
  }

  String _normalizeUrlForComparison(String? url) {
    if (url == null) return '';
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    final withoutTrailingSlash =
        lower.endsWith('/') ? lower.substring(0, lower.length - 1) : lower;
    return withoutTrailingSlash;
  }

  UserCategory _resolveCategoryForExperience(Experience experience) {
    if (experience.categoryId != null) {
      for (final category in _userCategories) {
        if (category.id == experience.categoryId) {
          return category;
        }
      }
    }

    final bool isUncategorized =
        experience.categoryId == null || experience.categoryId!.isEmpty;

    return UserCategory(
      id: experience.categoryId ?? 'uncategorized',
      name: isUncategorized ? 'Uncategorized' : 'Collection',
      icon: '📍',
      ownerUserId: experience.createdBy ?? 'system_default',
    );
  }

  Widget? _buildSourceActionButton(_DiscoveryFeedItem item) {
    final config = _resolveSourceButtonConfig(item.mediaUrl);
    if (config == null) return null;
    return _buildActionButton(
      icon: config.iconData,
      iconWidget: config.iconWidget,
      label: config.label,
      backgroundColor: config.backgroundColor,
      onPressed: () => _launchUrl(item.mediaUrl),
    );
  }

  Future<void> _handleBookmarkTapped(_DiscoveryFeedItem item) async {
    final List<Experience> initialExperiences =
        await _buildInitialExperiencesForSave(item);

    await _openSaveExperiencesSheet(
      initialExperiences: initialExperiences,
      mediaUrl: item.mediaUrl,
      feedItem: item,
    );
  }

  Future<List<Experience>> _buildInitialExperiencesForSave(
    _DiscoveryFeedItem item, {
    List<Experience>? seedExperiences,
  }) async {
    final List<Experience> linkedExperiences = List<Experience>.from(
        seedExperiences ?? await _getLinkedExperiencesForMedia(item.mediaUrl));

    final List<Experience> dedupedExperiences =
        _dedupeExperiencesById(linkedExperiences);

    if (dedupedExperiences.isEmpty) {
      return [_buildExperienceDraft(item.experience)];
    }

    final bool alreadyContainsPreview = dedupedExperiences.any(
      (exp) => _experienceMatchesPublic(exp, item.experience),
    );
    if (alreadyContainsPreview) {
      return dedupedExperiences;
    }

    final Experience draft = _buildExperienceDraft(item.experience);
    return [...dedupedExperiences, draft];
  }

  Future<void> _openSaveExperiencesSheet({
    required List<Experience> initialExperiences,
    required String mediaUrl,
    _DiscoveryFeedItem? feedItem,
  }) async {
    if (initialExperiences.isEmpty) return;

    final String? resultMessage = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SaveToExperiencesModal(
        initialExperiences: initialExperiences,
        mediaUrl: mediaUrl,
      ),
    );

    if (resultMessage == null || !mounted) return;

    if (feedItem != null) {
      feedItem.isMediaAlreadySaved.value = true;
    }
    _markMediaAsSaved(mediaUrl);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultMessage)),
    );
  }

  Future<List<Experience>> _getLinkedExperiencesForMedia(String mediaUrl) {
    if (mediaUrl.isEmpty) {
      return Future.value(const <Experience>[]);
    }

    return _linkedExperiencesFutures.putIfAbsent(mediaUrl, () async {
      try {
        final SharedMediaItem? mediaItem =
            await _experienceService.findSharedMediaItemByPath(mediaUrl);
        if (mediaItem == null || mediaItem.experienceIds.isEmpty) {
          return const <Experience>[];
        }

        final experiences = await _experienceService
            .getExperiencesByIds(mediaItem.experienceIds);
        experiences.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return experiences;
      } catch (e) {
        debugPrint('Failed to load linked experiences: $e');
        return const <Experience>[];
      }
    });
  }

  Future<void> _showLinkedExperiencesDialog(_DiscoveryFeedItem item) async {
    final mediaUrl = item.mediaUrl;
    if (mediaUrl.isEmpty) return;

    final experiences = await _getLinkedExperiencesForMedia(mediaUrl);
    if (!mounted) return;

    if (experiences.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No additional experiences linked yet.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Linked Experiences'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: experiences.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final experience = experiences[index];
                return ListTile(
                  title: Text(experience.name),
                  subtitle: Text(_formatExperienceSubtitle(experience)),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final initialExperiences =
                    await _buildInitialExperiencesForSave(
                  item,
                  seedExperiences: experiences,
                );
                if (!mounted) return;
                Future.microtask(() {
                  _openSaveExperiencesSheet(
                    initialExperiences: initialExperiences,
                    mediaUrl: mediaUrl,
                    feedItem: item,
                  );
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save All'),
            ),
          ],
        );
      },
    );
  }

  String _formatExperienceSubtitle(Experience experience) {
    final location = experience.location;
    final parts = <String>[];
    if ((location.city ?? '').trim().isNotEmpty) {
      parts.add(location.city!.trim());
    }
    if ((location.state ?? '').trim().isNotEmpty) {
      parts.add(location.state!.trim());
    }
    if (parts.isEmpty && (location.address ?? '').trim().isNotEmpty) {
      parts.add(location.address!.trim());
    }
    return parts.isNotEmpty ? parts.join(', ') : 'Location details unavailable';
  }

  Experience _buildExperienceDraft(PublicExperience publicExperience) {
    return publicExperience.toExperienceDraft();
  }

  List<Experience> _dedupeExperiencesById(List<Experience> experiences) {
    final Set<String> seen = <String>{};
    final List<Experience> deduped = [];
    for (final exp in experiences) {
      final String key = _experienceCacheKey(exp);
      if (seen.add(key)) {
        deduped.add(exp);
      }
    }
    return deduped;
  }

  String _experienceCacheKey(Experience experience) {
    if (experience.id.isNotEmpty) {
      return experience.id;
    }

    final location = experience.location;
    final buffer = StringBuffer()
      ..write(experience.name.trim().toLowerCase())
      ..write('|')
      ..write(location.placeId?.trim().toLowerCase() ?? '')
      ..write('|')
      ..write((location.address ?? '').trim().toLowerCase());
    return buffer.toString();
  }

  bool _experienceMatchesPublic(
    Experience savedExperience,
    PublicExperience publicExperience,
  ) {
    final String savedPlaceId = savedExperience.location.placeId?.trim() ?? '';
    final String publicPlaceId = publicExperience.placeID.trim();
    if (savedPlaceId.isNotEmpty && publicPlaceId.isNotEmpty) {
      return savedPlaceId == publicPlaceId;
    }

    final String savedName = savedExperience.name.trim().toLowerCase();
    final String publicName = publicExperience.name.trim().toLowerCase();
    if (savedName.isEmpty || publicName.isEmpty) {
      return false;
    }

    final String savedAddress =
        (savedExperience.location.address ?? '').trim().toLowerCase();
    final String publicAddress =
        (publicExperience.location.address ?? '').trim().toLowerCase();

    if (savedAddress.isNotEmpty && publicAddress.isNotEmpty) {
      return savedName == publicName && savedAddress == publicAddress;
    }

    return savedName == publicName;
  }

  Widget _buildPreviewForItem(_DiscoveryFeedItem item) {
    final url = item.mediaUrl;

    if (url.isEmpty) {
      return _buildFallbackPreview(
        icon: Icons.link_off,
        label: 'No preview available',
        description: 'This experience does not include a preview link.',
      );
    }

    final type = _classifyUrl(url);
    final mediaSize = MediaQuery.of(context).size;

    switch (type) {
      case _MediaType.tiktok:
        return SizedBox.expand(
          child: kIsWeb
              ? Center(
                  child: WebMediaPreviewCard(
                    url: url,
                    experienceName: item.experience.name,
                    onOpenPressed: () => _launchUrl(url),
                  ),
                )
              : TikTokPreviewWidget(
                  key: ValueKey('tiktok_$url'),
                  url: url,
                  launchUrlCallback: _launchUrl,
                  showControls: false,
                ),
        );
      case _MediaType.instagram:
        return SizedBox.expand(
          child: kIsWeb
              ? Center(
                  child: WebMediaPreviewCard(
                    url: url,
                    experienceName: item.experience.name,
                    onOpenPressed: () => _launchUrl(url),
                  ),
                )
              : instagram_widget.InstagramWebView(
                  key: ValueKey('instagram_$url'),
                  url: url,
                  height: mediaSize.height,
                  launchUrlCallback: _launchUrl,
                  onWebViewCreated: (_) {},
                  onPageFinished: (_) {},
                ),
        );
      case _MediaType.facebook:
        return SizedBox.expand(
          child: kIsWeb
              ? Center(
                  child: WebMediaPreviewCard(
                    url: url,
                    experienceName: item.experience.name,
                    onOpenPressed: () => _launchUrl(url),
                  ),
                )
              : FacebookPreviewWidget(
                  key: ValueKey('facebook_$url'),
                  url: url,
                  height: mediaSize.height,
                  onWebViewCreated: (_) {},
                  onPageFinished: (_) {},
                  launchUrlCallback: _launchUrl,
                  showControls: false,
                ),
        );
      case _MediaType.youtube:
        return SizedBox.expand(
          child: kIsWeb
              ? Center(
                  child: WebMediaPreviewCard(
                    url: url,
                    experienceName: item.experience.name,
                    onOpenPressed: () => _launchUrl(url),
                  ),
                )
              : YouTubePreviewWidget(
                  key: ValueKey('youtube_$url'),
                  url: url,
                  launchUrlCallback: _launchUrl,
                  showControls: false,
                  onWebViewCreated: (_) {},
                  height: mediaSize.height,
                ),
        );
      case _MediaType.maps:
        _mapsPreviewFutures[url] ??= Future.value({
          'location': item.experience.location,
          'placeName': item.experience.name,
          'mapsUrl': url,
          'website': item.experience.website,
        });
        return SizedBox.expand(
          child: MapsPreviewWidget(
            key: ValueKey('maps_$url'),
            mapsUrl: url,
            mapsPreviewFutures: _mapsPreviewFutures,
            getLocationFromMapsUrl: (requestedUrl) async {
              if (requestedUrl == url) {
                return {
                  'location': item.experience.location,
                  'placeName': item.experience.name,
                  'mapsUrl': url,
                  'website': item.experience.website,
                };
              }
              return null;
            },
            launchUrlCallback: _launchUrl,
            mapsService: _mapsService,
          ),
        );
      case _MediaType.image:
        return SizedBox.expand(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: Colors.grey.shade900,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackPreview(
                icon: Icons.broken_image_outlined,
                label: 'Image failed to load',
                description: 'Try opening this image in your browser.',
              );
            },
          ),
        );
      case _MediaType.generic:
        return SizedBox.expand(
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: GenericUrlPreviewWidget(
              key: ValueKey('generic_$url'),
              url: url,
              launchUrlCallback: _launchUrl,
            ),
          ),
        );
      case _MediaType.yelp:
        return _buildFallbackPreview(
          icon: Icons.link_off,
          label: 'Preview unavailable',
          description: 'This link cannot be previewed here. Tap the source button to open it externally.',
        );
    }
  }

  Widget _buildFallbackPreview({
    required IconData icon,
    required String label,
    String? description,
  }) {
    return Container(
      width: double.infinity,
      height: 360,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 56),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleShareTapped(_DiscoveryFeedItem item) async {
    if (_isShareInProgress) return;
    final messenger = ScaffoldMessenger.of(context);

    await showShareExperienceBottomSheet(
      context: context,
      onDirectShare: () async {
        final bool? shared = await _shareDiscoveryItemWithFriends(item);
        if (!mounted) return;
        if (shared == true) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Shared with friends!')),
          );
        }
      },
      onCreateLink: (
          {required String shareMode, required bool giveEditAccess}) async {
        if (_isShareInProgress || !mounted) {
          return;
        }
        setState(() {
          _isShareInProgress = true;
        });
        try {
          if (shareMode != 'separate_copy' || giveEditAccess) {
            debugPrint(
              'DiscoveryScreen: Share mode settings are not supported; proceeding with discovery share defaults.',
            );
          }
          final String shareUrl = await _discoveryShareService.createShare(
            experience: item.experience,
            mediaUrl: item.mediaUrl,
          );
          if (!mounted) return;
          Navigator.of(context).pop();
          final String shareText =
              'Check out this experience from Plendy! $shareUrl';
          await Share.share(shareText);
        } catch (e) {
          debugPrint('DiscoveryScreen: Failed to create share link: $e');
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content:
                    Text('Unable to generate a share link. Please try again.'),
              ),
            );
          }
        } finally {
          if (!mounted) return;
          setState(() {
            _isShareInProgress = false;
          });
        }
      },
    );
  }

  Future<bool?> _shareDiscoveryItemWithFriends(_DiscoveryFeedItem item) async {
    if (!mounted) return false;

    final Experience baseExperience =
        item.experience.toExperienceDraft().copyWith(
              imageUrls: _buildShareImageList(
                item.mediaUrl,
                item.experience.allMediaPaths,
              ),
            );

    final bool? shared = await showShareToFriendsModal(
      context: context,
      subjectLabel: item.experience.name,
      onSubmit: (recipientIds) async {
        await _experienceShareService.createDirectShare(
          experience: baseExperience,
          toUserIds: recipientIds,
          highlightedMediaUrl:
              item.mediaUrl, // Pass the specific media URL being viewed
        );
      },
    );
    return shared;
  }

  List<String> _buildShareImageList(String selectedUrl, List<String> allUrls) {
    final Set<String> seen = {};
    final List<String> ordered = [];

    void addUrl(String? url) {
      if (url == null) return;
      final String trimmed = url.trim();
      if (trimmed.isEmpty) return;
      if (seen.add(trimmed)) {
        ordered.add(trimmed);
      }
    }

    addUrl(selectedUrl);
    for (final url in allUrls) {
      addUrl(url);
    }

    return ordered;
  }

  _SourceButtonConfig? _resolveSourceButtonConfig(String url) {
    if (!_isNetworkUrl(url)) return null;
    final type = _classifyUrl(url);
    switch (type) {
      case _MediaType.instagram:
        return _SourceButtonConfig(
          label: 'Instagram',
          backgroundColor: const Color(0xFFE4405F),
          iconWidget: const FaIcon(
            FontAwesomeIcons.instagram,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.tiktok:
        return _SourceButtonConfig(
          label: 'TikTok',
          backgroundColor: Colors.black,
          iconWidget: const FaIcon(
            FontAwesomeIcons.tiktok,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.facebook:
        return _SourceButtonConfig(
          label: 'Facebook',
          backgroundColor: const Color(0xFF1877F2),
          iconWidget: const FaIcon(
            FontAwesomeIcons.facebookF,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.youtube:
        return _SourceButtonConfig(
          label: 'YouTube',
          backgroundColor: const Color(0xFFFF0000),
          iconWidget: const FaIcon(
            FontAwesomeIcons.youtube,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.maps:
        return _SourceButtonConfig(
          label: 'Maps',
          backgroundColor: const Color(0xFF4285F4),
          iconWidget: const FaIcon(
            FontAwesomeIcons.google,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.yelp:
        return _SourceButtonConfig(
          label: 'Yelp',
          backgroundColor: const Color(0xFFD32323),
          iconWidget: const FaIcon(
            FontAwesomeIcons.yelp,
            color: Colors.white,
            size: 20,
          ),
        );
      case _MediaType.image:
      case _MediaType.generic:
        return _SourceButtonConfig(
          label: 'Open Link',
          backgroundColor: Colors.blue.shade700,
          iconData: Icons.open_in_new,
        );
    }
  }

  bool _isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  _MediaType _classifyUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        _isLikelyImageUrl(lower)) {
      return _MediaType.image;
    }
    if (lower.contains('tiktok.com') || lower.contains('vm.tiktok.com')) {
      return _MediaType.tiktok;
    }
    if (lower.contains('instagram.com')) {
      return _MediaType.instagram;
    }
    if (lower.contains('facebook.com') ||
        lower.contains('fb.com') ||
        lower.contains('fb.watch')) {
      return _MediaType.facebook;
    }
    if (lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('youtube.com/shorts')) {
      return _MediaType.youtube;
    }
    if (lower.contains('yelp.com/biz') || lower.contains('yelp.to/')) {
      return _MediaType.yelp;
    }
    if (lower.contains('google.com/maps') ||
        lower.contains('maps.app.goo.gl') ||
        lower.contains('goo.gl/maps') ||
        lower.contains('g.co/kgs/') ||
        lower.contains('share.google/')) {
      return _MediaType.maps;
    }
    return _MediaType.generic;
  }

  bool _isLikelyImageUrl(String url) {
    final hasImageKeywords = ['img', 'image', 'photo', 'picture', 'media'];
    return hasImageKeywords.any(url.contains);
  }
}

class _DiscoveryFeedItem {
  _DiscoveryFeedItem({
    required this.experience,
    required this.mediaUrl,
  });

  final PublicExperience experience;
  final String mediaUrl;
  final ValueNotifier<bool?> isMediaAlreadySaved = ValueNotifier<bool?>(null);
}

enum _MediaType {
  tiktok,
  instagram,
  facebook,
  youtube,
  maps,
  image,
  yelp,
  generic,
}

class _SourceButtonConfig {
  const _SourceButtonConfig({
    this.iconData,
    this.iconWidget,
    required this.label,
    required this.backgroundColor,
  }) : assert(iconData != null || iconWidget != null);

  final IconData? iconData;
  final Widget? iconWidget;
  final String label;
  final Color backgroundColor;
}

class _CoverQuote {
  const _CoverQuote({
    required this.text,
    this.author,
  });

  final String text;
  final String? author;
}
