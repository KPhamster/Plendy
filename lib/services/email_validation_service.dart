import 'dart:async';
import 'package:email_validator/email_validator.dart' as email_validator_pkg;
import 'package:dnsolve/dnsolve.dart';

/// Result of email validation with detailed status
class EmailValidationResult {
  final bool isValid;
  final String? errorMessage;
  final EmailValidationStatus status;

  const EmailValidationResult({
    required this.isValid,
    this.errorMessage,
    required this.status,
  });

  factory EmailValidationResult.valid() {
    return const EmailValidationResult(
      isValid: true,
      status: EmailValidationStatus.valid,
    );
  }

  factory EmailValidationResult.invalid(String message, EmailValidationStatus status) {
    return EmailValidationResult(
      isValid: false,
      errorMessage: message,
      status: status,
    );
  }
}

/// Status codes for email validation
enum EmailValidationStatus {
  valid,
  empty,
  invalidFormat,
  disposableEmail,
  invalidDomain,
  noMxRecords,
  networkError,
  timeout,
}

/// Service for comprehensive email validation
/// 
/// Performs multi-layer validation:
/// 1. Format validation (RFC-compliant)
/// 2. Disposable email detection
/// 3. DNS MX record verification
class EmailValidationService {
  // Singleton instance
  static final EmailValidationService _instance = EmailValidationService._internal();
  factory EmailValidationService() => _instance;
  EmailValidationService._internal();

  // Cache for domain validation results (domain -> hasValidMX)
  final Map<String, _CachedResult> _domainCache = {};
  
  // Cache duration: 24 hours
  static const Duration _cacheDuration = Duration(hours: 24);
  
  // DNS timeout duration
  static const Duration _dnsTimeout = Duration(seconds: 5);

  /// Comprehensive list of disposable email domains
  /// Updated from https://github.com/disposable-email-domains/disposable-email-domains
  static const Set<String> _disposableDomains = {
    // Popular temporary email services
    '10minutemail.com',
    '10minutemail.net',
    '10minmail.com',
    'tempmail.com',
    'temp-mail.org',
    'temp-mail.io',
    'tempail.com',
    'guerrillamail.com',
    'guerrillamail.org',
    'guerrillamail.net',
    'guerrillamail.biz',
    'guerrillamail.de',
    'guerrillamailblock.com',
    'sharklasers.com',
    'grr.la',
    'spam4.me',
    'pokemail.net',
    'mailinator.com',
    'mailinator.net',
    'mailinator.org',
    'mailinator2.com',
    'mailinater.com',
    'mailinator.us',
    'throwaway.email',
    'throwawaymail.com',
    'getnada.com',
    'nada.email',
    'dispostable.com',
    'fakeinbox.com',
    'fakemailgenerator.com',
    'trashmail.com',
    'trashmail.net',
    'trashmail.org',
    'trashmail.ws',
    'yopmail.com',
    'yopmail.fr',
    'yopmail.net',
    'cool.fr.nf',
    'jetable.fr.nf',
    'nospam.ze.tc',
    'nomail.xl.cx',
    'mega.zik.dj',
    'speed.1s.fr',
    'courriel.fr.nf',
    'moncourrier.fr.nf',
    'monemail.fr.nf',
    'monmail.fr.nf',
    'maildrop.cc',
    'maildrop.ml',
    'mailnesia.com',
    'mailnull.com',
    'mintemail.com',
    'mohmal.com',
    'mohmal.im',
    'mohmal.in',
    'mohmal.tech',
    'discard.email',
    'discardmail.com',
    'discardmail.de',
    'emailondeck.com',
    'getairmail.com',
    'airmail.cc',
    'anonymbox.com',
    'anonymmail.net',
    'armyspy.com',
    'cuvox.de',
    'dayrep.com',
    'einrot.com',
    'fleckens.hu',
    'gustr.com',
    'jourrapide.com',
    'rhyta.com',
    'superrito.com',
    'teleworm.us',
    'inboxalias.com',
    'spamgourmet.com',
    'spamgourmet.net',
    'spamgourmet.org',
    'mytrashmail.com',
    'mt2009.com',
    'mt2014.com',
    'thankyou2010.com',
    'trash2009.com',
    'explodemail.com',
    'filzmail.com',
    'getonemail.com',
    'getonemail.net',
    'imgv.de',
    'kasmail.com',
    'mailbidon.com',
    'mail-temporaire.fr',
    'mailtemporaire.com',
    'mailtemporaire.fr',
    'tempr.email',
    'tmpmail.org',
    'tmpmail.net',
    'emailfake.com',
    'fakeinbox.cf',
    'fakeinbox.ga',
    'fakeinbox.ml',
    'fakeinbox.tk',
    'fakemail.fr',
    'mailforspam.com',
    'spamfree24.org',
    'spamfree24.de',
    'spamfree24.eu',
    'spamfree24.info',
    'spamfree24.net',
    'example.com', // RFC reserved
    'example.org', // RFC reserved
    'example.net', // RFC reserved
    'test.com', // Often used for testing
    // Additional common disposable domains
    'binkmail.com',
    'bobmail.info',
    'chammy.info',
    'devnullmail.com',
    'disposableemailaddresses.com',
    'dodgeit.com',
    'dodgit.com',
    'dodgit.org',
    'dumpyemail.com',
    'e4ward.com',
    'emailmiser.com',
    'emailsensei.com',
    'emailtemporario.com.br',
    'emailwarden.com',
    'enterto.com',
    'ephemail.net',
    'etranquil.com',
    'etranquil.net',
    'etranquil.org',
    'evopo.com',
    'fakedemail.com',
    'fastacura.com',
    'fastchevy.com',
    'fastchrysler.com',
    'fastkawasaki.com',
    'fastmazda.com',
    'fastmitsubishi.com',
    'fastnissan.com',
    'fastsubaru.com',
    'fastsuzuki.com',
    'fasttoyota.com',
    'fastyamaha.com',
    'fiifke.de',
    'fivemail.de',
    'fixmail.tk',
    'fizmail.com',
    'frapmail.com',
    'friendlymail.co.uk',
    'front14.org',
    'fux0ringduh.com',
    'garliclife.com',
    'gehensiull.com',
    'gelitik.in',
    'ghosttexter.de',
    'gishpuppy.com',
    'goemailgo.com',
    'gotmail.com',
    'gotmail.net',
    'gotmail.org',
    'great-host.in',
    'greensloth.com',
    'grish.de',
    'groupmail.com',
    'haltospam.com',
    'hatespam.org',
    'herp.in',
    'hidemail.de',
    'hidzz.com',
    'hmamail.com',
    'hochsitze.com',
    'hotpop.com',
    'hulapla.de',
    'hushmail.com',
    'ieatspam.eu',
    'ieatspam.info',
    'ieh-mail.de',
    'ignoremail.com',
    'ihateyoualot.info',
    'iheartspam.org',
    'imails.info',
    'imgof.com',
    'incognitomail.com',
    'incognitomail.net',
    'incognitomail.org',
    'infocom.zp.ua',
    'insorg-mail.info',
    'instant-mail.de',
    'ipoo.org',
    'irish2me.com',
    'iwi.net',
    'jetable.com',
    'jetable.net',
    'jetable.org',
    'jnxjn.com',
    'jsrsolutions.com',
    'kaspop.com',
    'keepmymail.com',
    'killmail.com',
    'killmail.net',
    'kir.ch.tc',
    'klassmaster.com',
    'klassmaster.net',
    'klzlv.com',
    'kulturbetrieb.info',
    'kurzepost.de',
    'lawlita.com',
    'letthemeatspam.com',
    'lhsdv.com',
    'lifebyfood.com',
    'link2mail.net',
    'litedrop.com',
    'lol.ovpn.to',
    'lookugly.com',
    'lopl.co.cc',
    'lortemail.dk',
    'lovemeleaveme.com',
    'lr78.com',
    'lroid.com',
    'm4ilweb.info',
    'maboard.com',
    'mail-hierarchie.net',
    'mail.by',
    'mail.mezimages.net',
    'mail.zp.ua',
    'mail114.net',
    'mail2rss.org',
    'mail333.com',
    'mail4trash.com',
    'mailblocks.com',
    'mailcatch.com',
    'mailcat.biz',
    'maildu.de',
    'maileater.com',
    'maileimer.de',
    'mailexpire.com',
    'mailfa.tk',
    'mailfork.com',
    'mailguard.me',
    'mailin8r.com',
    'mailme.ir',
    'mailme.lv',
    'mailme24.com',
    'mailmetrash.com',
    'mailmoat.com',
    'mailnator.com',
    'mailorg.org',
    'mailsac.com',
    'mailseal.de',
    'mailshell.com',
    'mailsiphon.com',
    'mailslapping.com',
    'mailslite.com',
    'mailzilla.com',
    'mailzilla.org',
    'makemetheking.com',
    'manybrain.com',
    'mbx.cc',
    'meinspamschutz.de',
    'meltmail.com',
    'messagebeamer.de',
    'mezimages.net',
    'mierdamail.com',
    'migmail.pl',
    'migumail.com',
    'moburl.com',
    'monumentmail.com',
    'msa.minsmail.com',
    'msb.minsmail.com',
    'msh.minsmail.com',
    'mxfuel.com',
    'mynetstore.de',
    'mypacks.net',
    'myspaceinc.com',
    'myspaceinc.net',
    'myspacepimpedup.com',
    'neomailbox.com',
    'nervmich.net',
    'nervtmansen.de',
    'netmails.com',
    'netmails.net',
    'netzidiot.de',
    'neverbox.com',
    'nice-4u.com',
    'nincsmail.hu',
    'nmail.cf',
    'nobulk.com',
    'noclickemail.com',
    'nogmailspam.info',
    'nomail2me.com',
    'nomorespamemails.com',
    'nospam4.us',
    'nospamfor.us',
    'nospammail.net',
    'nospamthanks.info',
    'notmailinator.com',
    'nowmymail.com',
    'nurfuerspam.de',
    'nus.edu.sg',
    'nwldx.com',
    'objectmail.com',
    'obobbo.com',
    'odnorazovoe.ru',
    'oneoffemail.com',
    'onewaymail.com',
    'onlatedotcom.info',
    'online.ms',
    'oopi.org',
    'opayq.com',
    'ordinaryamerican.net',
    'otherinbox.com',
    'ourklips.com',
    'outlawspam.com',
    'ovpn.to',
    'owlpic.com',
    'pancakemail.com',
    'pjjkp.com',
    'plexolan.de',
    'poczta.onet.pl',
    'politikerclub.de',
    'poofy.org',
    'pookmail.com',
    'privacy.net',
    'privy-mail.com',
    'privymail.de',
    'proxymail.eu',
    'prtnx.com',
    'punkass.com',
    'putthisinyourspamdatabase.com',
    'qq.com', // Chinese email - sometimes used for spam, but legitimate users exist
    'quickinbox.com',
    'quickmail.nl',
    'rcpt.at',
    'reallymymail.com',
    'realtyalerts.ca',
    'recode.me',
    'recursor.net',
    'recyclemail.dk',
    'regbypass.com',
    'regbypass.comsafe-mail.net',
    'rejectmail.com',
    'remail.cf',
    'remail.ga',
    'rklips.com',
    'rmqkr.net',
    'royal.net',
    'rppkn.com',
    'rtrtr.com',
    's0ny.net',
    'safe-mail.net',
    'safersignup.de',
    'safetymail.info',
    'safetypost.de',
    'sandelf.de',
    'saynotospams.com',
    'schafmail.de',
    'schrott-email.de',
    'secretemail.de',
    'secure-mail.biz',
    'selfdestructingmail.com',
    'senseless-entertainment.com',
    'server.ms.selfip.net',
    'sharedmailbox.org',
    'shieldedmail.com',
    'shieldemail.com',
    'shiftmail.com',
    'shitmail.me',
    'shortmail.net',
    'shut.name',
    'shut.ws',
    'sibmail.com',
    'sinnlos-mail.de',
    'siteposter.net',
    'skeefmail.com',
    'slaskpost.se',
    'slopsbox.com',
    'slowfoodfoothills.xyz',
    'smellfear.com',
    'smellrear.com',
    'snakemail.com',
    'sneakemail.com',
    'sneakmail.de',
    'snkmail.com',
    'sofimail.com',
    'sofort-mail.de',
    'softpls.asia',
    'sogetthis.com',
    'sohu.com', // Chinese email - sometimes used for spam, but legitimate users exist
    'soisz.com',
    'solmail.info',
    'soodomail.com',
    'soodonims.com',
    'spam.la',
    'spam.su',
    'spamail.de',
    'spamavert.com',
    'spambob.com',
    'spambob.net',
    'spambob.org',
    'spambog.com',
    'spambog.de',
    'spambog.net',
    'spambog.ru',
    'spambox.info',
    'spambox.irishspringrealty.com',
    'spambox.us',
    'spamcannon.com',
    'spamcannon.net',
    'spamcero.com',
    'spamcon.org',
    'spamcorptastic.com',
    'spamcowboy.com',
    'spamcowboy.net',
    'spamcowboy.org',
    'spamday.com',
    'spamex.com',
    'spamfree.eu',
    'spamfree24.com',
    'spamgoes.in',
    'spamherelots.com',
    'spamhereplease.com',
    'spamhole.com',
    'spamify.com',
    'spaminator.de',
    'spamkill.info',
    'spaml.com',
    'spaml.de',
    'spammotel.com',
    'spamobox.com',
    'spamoff.de',
    'spamsalad.in',
    'spamslicer.com',
    'spamspot.com',
    'spamstack.net',
    'spamthis.co.uk',
    'spamtroll.net',
    'spikio.com',
    'spoofmail.de',
    'squizzy.de',
    'ssoia.com',
    'startkeys.com',
    'stinkefinger.net',
    'stop-my-spam.cf',
    'stop-my-spam.com',
    'stop-my-spam.ga',
    'stop-my-spam.ml',
    'stop-my-spam.tk',
    'streetwisemail.com',
    'stuffmail.de',
    'super-auswahl.de',
    'supergreatmail.com',
    'supermailer.jp',
    'superstachel.de',
    'suremail.info',
    'svk.jp',
    'sweetxxx.de',
    'tafmail.com',
    'tagyourself.com',
    'talkinator.com',
    'tapchicuoihoi.com',
    'techemail.com',
    'techgroup.me',
    'teewars.org',
    'teleosaurs.xyz',
    'teleworm.com',
    'temp.emeraldwebmail.com',
    'temp.headstrong.de',
    'tempalias.com',
    'tempe-mail.com',
    'tempemail.biz',
    'tempemail.co.za',
    'tempemail.com',
    'tempemail.net',
    'tempinbox.co.uk',
    'tempinbox.com',
    'tempmail.co',
    'tempmail.de',
    'tempmail.eu',
    'tempmail.it',
    'tempmail.net',
    'tempmail.us',
    'tempmail2.com',
    'tempmaildemo.com',
    'tempmailer.com',
    'tempmailer.de',
    'tempmailer.net',
    'tempomail.fr',
    'temporarily.de',
    'temporarioemail.com.br',
    'temporaryemail.net',
    'temporaryemail.us',
    'temporaryforwarding.com',
    'temporaryinbox.com',
    'temporarymailaddress.com',
    'tempthe.net',
    'tempymail.com',
    'thanksnospam.info',
    'thecloudindex.com',
    'thisisnotmyrealemail.com',
    'throam.com',
    'throwam.com',
    'throwawayemailaddress.com',
    'tilien.com',
    'tittbit.in',
    'tmailinator.com',
    'toiea.com',
    'tonymanso.com',
    'toomail.biz',
    'topranklist.de',
    'tradermail.info',
    'trash-amil.com',
    'trash-mail.at',
    'trash-mail.com',
    'trash-mail.de',
    'trash-mail.ga',
    'trash-mail.gq',
    'trash-mail.ml',
    'trash-mail.tk',
    'trash2010.com',
    'trash2011.com',
    'trashbox.eu',
    'trashdevil.com',
    'trashdevil.de',
    'trashemail.de',
    'trashmail.at',
    'trashmail.de',
    'trashmail.me',
    'trashmailer.com',
    'trashymail.com',
    'trashymail.net',
    'trbvm.com',
    'trickmail.net',
    'trillianpro.com',
    'trimix.cn',
    'trollbot.org',
    'tropicalbass.info',
    'trungtamtoeic.com',
    'ttszuo.xyz',
    'tualias.com',
    'turual.com',
    'twinmail.de',
    'tyldd.com',
    'ubismail.net',
    'uggsrock.com',
    'umail.net',
    'upliftnow.com',
    'uplipht.com',
    'uroid.com',
    'us.af',
    'valemail.net',
    'venompen.com',
    'veryrealemail.com',
    'viditag.com',
    'viralplays.com',
    'vkcode.ru',
    'vpn.st',
    'vsimcard.com',
    'vubby.com',
    'wasteland.rfc822.org',
    'webemail.me',
    'webm4il.info',
    'webuser.in',
    'wee.my',
    'weg-werf-email.de',
    'wegwerf-emails.de',
    'wegwerfadresse.de',
    'wegwerfemail.com',
    'wegwerfemail.de',
    'wegwerfemail.net',
    'wegwerfemail.org',
    'wegwerfemails.de',
    'wegwerfmail.de',
    'wegwerfmail.info',
    'wegwerfmail.net',
    'wegwerfmail.org',
    'wetrainbayarea.com',
    'wetrainbayarea.org',
    'wh4f.org',
    'whatiaas.com',
    'whatpaas.com',
    'whopy.com',
    'whtjddn.33mail.com',
    'whyspam.me',
    'wilemail.com',
    'willhackforfood.biz',
    'willselfdestruct.com',
    'winemaven.info',
    'wolfsmail.tk',
    'wollan.info',
    'worldspace.link',
    'wronghead.com',
    'wuzup.net',
    'wuzupmail.net',
    'wwwnew.eu',
    'x.ip6.li',
    'xagloo.co',
    'xagloo.com',
    'xcompress.com',
    'xemaps.com',
    'xents.com',
    'xmaily.com',
    'xoxy.net',
    'yapped.net',
    'yep.it',
    'yogamaven.com',
    'you-spam.com',
    'yourdomain.com',
    'ypmail.webarnak.fr.eu.org',
    'yuurok.com',
    'za.com',
    'zehnminuten.de',
    'zehnminutenmail.de',
    'zetmail.com',
    'zippymail.info',
    'zoaxe.com',
    'zoemail.com',
    'zoemail.net',
    'zoemail.org',
    'zomg.info',
    'zxcv.com',
    'zxcvbnm.com',
    'zzz.com',
  };

  /// Validate email format using RFC-compliant validation
  bool isValidFormat(String email) {
    if (email.isEmpty) return false;
    return email_validator_pkg.EmailValidator.validate(email);
  }

  /// Check if email is from a disposable/temporary email provider
  bool isDisposableEmail(String email) {
    if (email.isEmpty) return false;
    
    final atIndex = email.lastIndexOf('@');
    if (atIndex == -1 || atIndex == email.length - 1) return false;
    
    final domain = email.substring(atIndex + 1).toLowerCase();
    return _disposableDomains.contains(domain);
  }

  /// Extract domain from email
  String? extractDomain(String email) {
    final atIndex = email.lastIndexOf('@');
    if (atIndex == -1 || atIndex == email.length - 1) return null;
    return email.substring(atIndex + 1).toLowerCase();
  }

  /// Check if domain has valid MX records using DNS lookup
  Future<bool> hasValidMxRecords(String domain) async {
    // Check cache first
    final cached = _domainCache[domain];
    if (cached != null && !cached.isExpired) {
      return cached.hasValidMx;
    }

    try {
      final dnSolve = DNSolve();
      
      // Query MX records with timeout
      final response = await dnSolve
          .lookup(domain, type: RecordType.mx)
          .timeout(_dnsTimeout);

      // Check if we got valid MX records
      final hasMx = response.answer != null && 
                    response.answer!.records != null &&
                    response.answer!.records!.isNotEmpty &&
                    response.answer!.records!.any((record) => record.data.isNotEmpty);

      // Cache the result
      _domainCache[domain] = _CachedResult(hasValidMx: hasMx);

      return hasMx;
    } on TimeoutException {
      print('DNS lookup timeout for domain: $domain');
      // On timeout, assume valid (don't block registration)
      return true;
    } catch (e) {
      print('DNS lookup error for domain $domain: $e');
      // On error, try fallback: check if domain resolves at all
      return await _fallbackDomainCheck(domain);
    }
  }

  /// Fallback check: verify domain has any DNS records (A or AAAA)
  Future<bool> _fallbackDomainCheck(String domain) async {
    try {
      final dnSolve = DNSolve();
      
      // Try A record lookup
      final aResponse = await dnSolve
          .lookup(domain, type: RecordType.A)
          .timeout(const Duration(seconds: 3));

      if (aResponse.answer != null && 
          aResponse.answer!.records != null &&
          aResponse.answer!.records!.isNotEmpty) {
        _domainCache[domain] = _CachedResult(hasValidMx: true);
        return true;
      }

      // Try AAAA record lookup (IPv6)
      final aaaaResponse = await dnSolve
          .lookup(domain, type: RecordType.aaaa)
          .timeout(const Duration(seconds: 3));

      final hasRecords = aaaaResponse.answer != null && 
                         aaaaResponse.answer!.records != null &&
                         aaaaResponse.answer!.records!.isNotEmpty;

      _domainCache[domain] = _CachedResult(hasValidMx: hasRecords);
      return hasRecords;
    } catch (e) {
      print('Fallback DNS check failed for domain $domain: $e');
      // Cache as invalid but allow registration (network might be down)
      return true;
    }
  }

  /// Comprehensive email validation
  /// 
  /// Performs validation in order:
  /// 1. Empty check
  /// 2. Format validation (RFC-compliant)
  /// 3. Disposable email detection
  /// 4. DNS MX record verification
  /// 
  /// Returns [EmailValidationResult] with detailed status
  Future<EmailValidationResult> validateEmail(String email) async {
    final trimmedEmail = email.trim();

    // 1. Empty check
    if (trimmedEmail.isEmpty) {
      return EmailValidationResult.invalid(
        'Please enter your email',
        EmailValidationStatus.empty,
      );
    }

    // 2. Format validation
    if (!isValidFormat(trimmedEmail)) {
      return EmailValidationResult.invalid(
        'Please enter a valid email address',
        EmailValidationStatus.invalidFormat,
      );
    }

    // 3. Disposable email check
    if (isDisposableEmail(trimmedEmail)) {
      return EmailValidationResult.invalid(
        'Temporary email addresses are not allowed',
        EmailValidationStatus.disposableEmail,
      );
    }

    // 4. Extract domain and check MX records
    final domain = extractDomain(trimmedEmail);
    if (domain == null) {
      return EmailValidationResult.invalid(
        'Please enter a valid email address',
        EmailValidationStatus.invalidFormat,
      );
    }

    try {
      final hasMx = await hasValidMxRecords(domain);
      if (!hasMx) {
        return EmailValidationResult.invalid(
          'This email domain does not appear to exist',
          EmailValidationStatus.noMxRecords,
        );
      }
    } on TimeoutException {
      // On timeout, allow registration but log
      print('MX record check timed out for: $domain');
    } catch (e) {
      // On network error, allow registration but log
      print('MX record check failed for $domain: $e');
    }

    return EmailValidationResult.valid();
  }

  /// Synchronous validation (format and disposable check only)
  /// Use this for instant feedback before async validation
  EmailValidationResult validateEmailSync(String email) {
    final trimmedEmail = email.trim();

    if (trimmedEmail.isEmpty) {
      return EmailValidationResult.invalid(
        'Please enter your email',
        EmailValidationStatus.empty,
      );
    }

    if (!isValidFormat(trimmedEmail)) {
      return EmailValidationResult.invalid(
        'Please enter a valid email address',
        EmailValidationStatus.invalidFormat,
      );
    }

    if (isDisposableEmail(trimmedEmail)) {
      return EmailValidationResult.invalid(
        'Temporary email addresses are not allowed',
        EmailValidationStatus.disposableEmail,
      );
    }

    // Format and disposable checks passed
    return EmailValidationResult.valid();
  }

  /// Clear the domain cache
  void clearCache() {
    _domainCache.clear();
  }
}

/// Cached validation result with expiration
class _CachedResult {
  final bool hasValidMx;
  final DateTime timestamp;

  _CachedResult({required this.hasValidMx}) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp) > EmailValidationService._cacheDuration;
}
