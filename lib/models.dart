import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;

import 'utils.dart';

var _videoExtensions = RegExp(
    r'\.(3g2|3gp|3gp2|3gpp|amv|asf|avi|divx|drc|dv|f4v|flv|gvi|gxf|ismv|iso|m1v|m2v|m2t|m2ts|m4v|mkv|mov|mp2|mp2v|mp4|mp4v|mpe|mpeg|mpeg1|mpeg2|mpeg4|mpg|mpv2|mts|mtv|mxf|mxg|nsv|nut|nuv|ogm|ogv|ogx|ps|rec|rm|rmvb|tod|ts|tts|vob|vro|webm|wm|wmv|wtv|xesc)$');

var _audioExtensions = RegExp(
    r'\.(3ga|a52|aac|ac3|adt|adts|aif|aifc|aiff|alac|amr|aob|ape|awb|caf|dts|flac|it|m4a|m4b|m4p|mid|mka|mlp|mod|mpa|mp1|mp2|mp3|mpc|mpga|oga|ogg|oma|opus|ra|ram|rmi|s3m|spx|tta|voc|vqf|w64|wav|wma|wv|xa|xm)$');

var _playlistExtensions = RegExp(
    r'\.(asx|b4s|cue|ifo|m3u|m3u8|pls|ram|rar|sdp|vlc|xspf|wax|wvx|zip|conf)');

var _audioTranslations = RegExp(
    r"^(Audio|_Audio|Ameslaw|Aodio|Audioa|Audiu|Deng|Dźwięk|Ekirikuhurirwa|Endobozi|Fuaim|Fuaim|Garsas|Hang|Hljóð|Leo|Ljud|Lyd|M_adungan|Ma giwinyo|Odio|Ojoo|Oudio|Ovoz|Sain|Ses|Sonido|Səs|Umsindo|Zvok|Zvuk|Zëri|Àudio|Áudio|Ääni|Ήχος|Аудио|Аўдыё|Дуу|Дыбыс|Звук|Ձայն|שמע|آڈیو, صدا|ئۈن|آڈیو|دەنگ|صدا|غږيز|अडिअ'|अडियो|आडियो|ध्वनी|অডিঅ'|অডিও|ਆਡੀਓ|ઓડિયો|ଅଡ଼ିଓ|ஒலி|శ్రవ్యకం|ಧ್ವನಿ|ഓഡിയോ|ශ්‍රව්‍ය|เสียง|အသံ|აუდიო|ተሰሚ|ድምፅ|អូឌីយ៉ូ|オーディオ|音訊|音频|오디오)$");

var _codecTranslations = RegExp(
    r"^(Codec|Bonez|Codifica|Codificador|Cudecu|Còdec|Códec|Dekko|Enkusike|i-Codec|Kodavimas|Kodek|Kodeka|Kodeks|Kodlayıcı/Çözücü|Koodek|Koodekki|Kóðalykill (codec)|Kôdek|Scéim Comhbhrúite|Кодек|Кодэк|Կոդեկ|מקודד/מפענח|كود يەشكۈچ|كوديك|کوڈیک|کوډېک|کُدک|کۆدێک|कोडेक|কোডেক|કોડેક|କୋଡେକ୍|கோடக்|కొడెక్|ಸಂಕೇತಕ|കോഡെക്ക്|කොඩෙක්|ตัวอ่าน-ลงรหัส|კოდეკი|ኮዴክ|កូដិក|コーデック|編解碼器|编解码器|코덱)$");

var _descriptionTranslations = RegExp(
    r"^(Description|Apraksts|Aprašymas|Açıklama|Beschreibung|Beschrijving|Beskriuwing|Beskrivelse|Beskrivning|Beskrywing|Cifagol|Cur síos|Descrición|Descriere|Descripcion|Descripció|Descripción|Descrizion|Descrizione|Descrição|Deskribapena|Deskripsi|Deskrivadur|Discrijhaedje|Discrizzione|Disgrifiad|Ennyinyonyola|Enshoborora|Fa'amatalaga|Hedef|Incazelo|Keterangan|Kirjeldus|Kuvaus|Leírás|Lýsing|Mô tả|Opis|Popis|Përshkrimi|Skildring|Ta’rifi|Te lok|Tuairisgeul|Περιγραφή|Апісанне|Баяндама|Опис|Описание|Сипаттама|Тайлбар|Тасвирлама|Նկարագրություն|תיאור|الوصف|سپړاوی|شرح|وضاحت|پەسن|چۈشەندۈرۈش|बेखेवथि|वर्णन|विवरण|বর্ণনা|বিবরণ|বিৱৰণ|ਵੇਰਵਾ|વર્ણન|ବିବରଣୀ|விவரம்|వివరణ|ವಿವರಣೆ|വിവരണം|විස්තරය|รายละเอียด|ဖော်ပြချက်|აღწერილობა|መግለጫ|សេចក្ដី​ពណ៌នា|描述|說明|説明|설명)$");

var _languageTranslations = RegExp(
    r"^(Language|Bahasa|Bahasa|Cànan|Dil|Gagana|Gjuha|Hizkuntza|Iaith|Idioma|Jazyk|Jezik|Kalba|Keel|Kieli|Langue|Leb|Lenga|Lenghe|Limbă|Lingaedje|Lingua|Llingua|Ngôn ngữ|Nyelv|Olulimi|Orurimi|Sprache|Språk|Taal|Teanga|Til|Tungumál|Ulimi|Valoda|Wybór języka|Yezh|Ziman|Ɗemngal|Γλώσσα|Език|Мова|Тел|Тил|Тілі|Хэл|Язык|Језик|Լեզու|שפה|اللغة|تىل|زبان|زمان|ژبه|भाषा|राव|ভাষা|ਭਾਸ਼ਾ|ભાષા|ଭାଷା|மொழி|భాష|ಭಾಷೆ|ഭാഷ|භාෂාව|ภาษา|ဘာသာစကား|ენა|ቋንቋ|ቋንቋ|ភាសា|言語|語言|语言|언어)$");

var _subtitleTranslations = RegExp(
    r"^(Subtitle|Altyazı|Azpititulua|Binnivîs/OSD|Emitwe|Felirat|Fo-thiotal|Fotheideal|Gagana fa'aliliu|Isdeitlau|Istitl|Izihlokwana|Legenda|Legendas|Lestiitol|Napisy|Omutwe ogwokubiri|Onderskrif|Ondertitel|Phụ đề|Podnapisi|Podnaslov|Podtitl|Sarikata|Sortite|Sostítols|Sot titul|Sottotitoli|Sottutitulu|Sous-titres|Subtiiter|Subtitlu|Subtitol|Subtitr|Subtitrai|Subtitrs|Subtitulo|Subtítol|Subtítulo|Subtítulos|Subtítulu|Tekstitys|Terjemahan|Texti|Titra|Titulky|Titulky|Undertekst|Undertext|Undertitel|Υπότιτλος|Дэд бичвэр|Превод|Субтитр|Субтитри|Субтитрлер|Субтитры|Субтитрі|Субтытры|Титл|Ենթագիր|अनुवाद पट्टी|उपशीर्षक|दालाय-बिमुं|উপশিৰোনাম|বিকল্প নাম|সাবটাইটেল|ਸਬ-ਟਾਈਟਲ|ઉપશીર્ષક|ଉପଟାଇଟେଲ୍‌|துணை உரை|ఉపశీర్షిక|ಉಪಶೀರ್ಷಿಕೆ|ഉപശീര്‍ഷകം|උපසිරැසි|บทบรรยาย|စာတန်းထိုး|ტიტრები|ንዑስ አርእስት|ጽሁፋዊ ትርጉሞች|ចំណង​ជើង​រង|字幕|자막)$");

var _typeTranslations = RegExp(
    r"^(Type|Cineál|Cure|Ekyika|Fannu|Handiika|Itū'āiga|Jenis|Kite|Liik|Loại|Math|Mota|Rizh|Seòrsa|Sôre|Tegund|Tip|Tipas|Tipe|Tipi|Tipo|Tips|Tipu|Tipus|Turi|Typ|Typo|Tyyppi|Típus|Tür|Uhlobo|Vrsta|Τύπος|Врста|Тип|Түрі|Түрү|Төр|Төрөл|Տեսակ|סוג|تىپى|جۆر|نوع|ٹایِپ|ډول|टंकलेखन करा|टाइप|प्रकार|रोखोम|ধরন|প্রকার|প্ৰকাৰ|ਟਾਈਪ|પ્રકાર|ପ୍ରକାର|வகை|రకం|ಪ್ರಕಾರ|തരം|වර්ගය|ประเภท|အမျိုးအစား|ტიპი|አይነት|ប្រភេទ|タイプ|类型|類型|형식)$");

enum OperatingSystem { linux, macos, windows }

Map<OperatingSystem, String> osNames = {
  OperatingSystem.linux: 'Linux',
  OperatingSystem.macos: 'macOS',
  OperatingSystem.windows: 'Windows',
};

class BrowseItem {
  String type, name, path, uri;

  BrowseItem(
    this.type,
    this.name,
    this.path,
    this.uri,
  );

  BrowseItem.fromUrl(String url)
      : uri = url.startsWith(urlRegExp) ? url : 'https://$url',
        type = 'web',
        path = '',
        name = '';

  /// Sending a directory: url when enqueueing makes a directory display as directory in the VLC
  /// playlist instead of as a generic file.
  String get playlistUri {
    if (isDir) return uri.replaceAll(RegExp(r'^file'), 'directory');
    return uri;
  }

  IconData get icon {
    if (isDir) {
      return Icons.folder;
    }
    if (isWeb) {
      return Icons.public;
    }
    if (isAudio) {
      return Icons.audiotrack;
    }
    if (isVideo) {
      return Icons.movie;
    }
    if (isPlaylist) {
      return Icons.list;
    }
    return Icons.insert_drive_file;
  }

  bool get isAudio => _audioExtensions.hasMatch(path);

  bool get isDir => type == 'dir';

  bool get isFile => type == 'file';

  bool get isPlaylist => _playlistExtensions.hasMatch(path);

  bool get isSupportedMedia => isAudio || isVideo || isWeb;

  bool get isVideo => _videoExtensions.hasMatch(path);

  bool get isWeb => type == 'web';

  String get title => isVideo ? cleanVideoTitle(name, keepExt: isFile) : name;

  BrowseItem.fromJson(Map<String, dynamic> json)
      : type = json['type'],
        name = json['name'],
        path = json['path'],
        uri = json['uri'];

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'path': path,
        'uri': uri,
      };

  @override
  String toString() => 'BrowseItem(${toJson()})';
}

enum BrowseResultIntent { play, enqueue }

class BrowseResult {
  BrowseItem item;
  BrowseResultIntent intent;
  BrowseResult(this.item, this.intent);
}

// ignore: unused_element
const _emulatorLocalhost = '10.0.2.2';

const defaultPort = '8080';
const defaultPassword = 'vlcplayer';

var _ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
var _numericPattern = RegExp(r'^\d+$');

class Connection {
  late String _ip = '';
  late String _port = defaultPort;
  late String _password = defaultPassword;

  String? _ipError;
  String? _portError;
  String? _passwordError;

  Connection();

  String get ip => _ip;
  String get port => _port;
  String get password => _password;
  get ipError => _ipError;
  get portError => _portError;
  get passwordError => _passwordError;

  String get authority => '$_ip:$_port';

  /// The connection stored in [Settings] will only have an IP if it's been
  /// successfully tested.
  bool get hasIp => _ip.isNotEmpty;

  bool get isValid =>
      _ipError == null && _portError == null && _passwordError == null;

  bool get isNotValid => !isValid;

  set ip(String value) {
    if (value.trim().isEmpty) {
      _ipError = 'An IP address is required';
    } else if (!_ipPattern.hasMatch(value)) {
      _ipError = 'Must have 4 parts separated by periods';
    } else {
      _ipError = null;
    }
    _ip = value;
  }

  set port(String value) {
    _port = value;
    if (value.trim().isEmpty) {
      _portError = 'A port number is required';
    } else if (!_numericPattern.hasMatch(value)) {
      _portError = 'Must be all digits';
    } else {
      _portError = null;
    }
    _port = value;
  }

  set password(String value) {
    if (value.trim().isEmpty) {
      _passwordError = 'A password is required';
    } else {
      _passwordError = null;
    }
    _password = value;
  }

  Connection.fromJson(Map<String, dynamic> json) {
    ip = json['ip'] ?? '';
    port = json['port'] ?? defaultPort;
    password = json['password'] ?? defaultPassword;
  }

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'password': password,
      };
}

class Settings {
  final SharedPreferences _prefs;

  late bool blurredCoverBg;
  late bool dense;
  late Connection connection;

  Settings(this._prefs) {
    Map<String, dynamic> json =
        jsonDecode(_prefs.getString('settings') ?? '{}');
    blurredCoverBg = json['blurredCoverBg'] ?? true;
    connection = Connection.fromJson(json['connection'] ?? {});
    dense = json['dense'] ?? false;
  }

  Map<String, dynamic> toJson() => {
        'blurredCoverBg': blurredCoverBg,
        'connection': connection,
        'dense': dense,
      };

  save() {
    _prefs.setString('settings', jsonEncode(this));
  }
}

class LanguageTrack {
  String name;
  int streamNumber;

  LanguageTrack(this.name, this.streamNumber);

  @override
  String toString() {
    return '$name ($streamNumber)';
  }
}

class Equalizer {
  late bool enabled;
  late List<Preset> presets;
  late List<Band> bands;
  late double preamp;

  @override
  String toString() {
    if (!enabled) {
      return 'Equalizer(off)';
    }
    return 'Equalizer(preamp: ${preamp.toStringAsFixed(1)}, bands: ${bands.map((b) => b.value.toStringAsFixed(1)).join(', ')})';
  }
}

class Band {
  int id;
  double value;

  Band(this.id, this.value);
}

class Preset {
  int id;
  String name;

  Preset(this.id, this.name);
}

String findFirstElementText(xml.XmlDocument document, String name,
    [String fallback = '']) {
  var elements = document.findAllElements(name);
  if (elements.isNotEmpty) {
    return elements.first.text;
  }
  return fallback;
}

String findFirstChildElementText(xml.XmlElement element, String name,
    [String fallback = '']) {
  var elements = element.findElements(name);
  if (elements.isNotEmpty) {
    return elements.first.text;
  }
  return fallback;
}

class VlcStatusResponse {
  xml.XmlDocument document;

  List<LanguageTrack>? _audioTracks;
  List<LanguageTrack>? _subtitleTracks;
  Map<String, String>? _info;

  VlcStatusResponse(this.document);

  String get state => findFirstElementText(document, 'state');

  Duration get time =>
      Duration(seconds: int.parse(findFirstElementText(document, 'time', '0')));

  Duration get length => Duration(
      seconds: int.parse(findFirstElementText(document, 'length', '0')));

  int get volume {
    return int.parse(findFirstElementText(document, 'volume', '256'));
  }

  double get rate => double.parse(document.findAllElements('rate').first.text);

  Map<String, String> get _metadata {
    if (_info == null) {
      xml.XmlElement? category;
      var informations = document.rootElement.findElements('information');
      if (informations.isNotEmpty) {
        var categories = informations.first.findElements('category');
        if (categories.isNotEmpty) {
          category = categories.first;
        }
      }
      _info = category != null
          ? {
              for (var el in category.findElements('info'))
                el.getAttribute('name') ?? '': el.text
            }
          : {};
    }
    return _info!;
  }

  String get title => _metadata['title'] ?? _metadata['filename'] ?? '';

  String get artist => _metadata['artist'] ?? '';

  String get artworkUrl => _metadata['artwork_url'] ?? '';

  bool get fullscreen => findFirstElementText(document, 'fullscreen') == 'true';

  bool get repeat => findFirstElementText(document, 'repeat') == 'true';

  bool get random => findFirstElementText(document, 'random') == 'true';

  bool get loop => findFirstElementText(document, 'loop') == 'true';

  String get currentPlId => findFirstElementText(document, 'currentplid', '-1');

  String get version => findFirstElementText(document, 'version');

  List<LanguageTrack> get audioTracks {
    return _audioTracks ??= _getLanguageTracks(_audioTranslations);
  }

  List<LanguageTrack> get subtitleTracks {
    return _subtitleTracks ??= _getLanguageTracks(_subtitleTranslations);
  }

  Equalizer get equalizer {
    var equalizer = Equalizer();
    var el = document.rootElement.findElements('equalizer').first;
    equalizer.enabled = el.firstChild != null;
    if (!equalizer.enabled) {
      return equalizer;
    }
    equalizer.presets = el
        .findAllElements('preset')
        .map((el) => Preset(
              int.parse(el.getAttribute('id')!),
              el.text,
            ))
        .toList();
    equalizer.presets.sort((a, b) => a.id - b.id);
    equalizer.bands = el
        .findAllElements('band')
        .map((el) => Band(
              int.parse(el.getAttribute('id')!),
              double.parse(el.text),
            ))
        .toList();
    equalizer.bands.sort((a, b) => a.id - b.id);
    equalizer.preamp = double.parse(el.findElements('preamp').first.text);
    return equalizer;
  }

  List<LanguageTrack> _getLanguageTracks(RegExp type) {
    List<LanguageTrack> tracks = [];
    document.findAllElements('category').forEach((category) {
      Map<String, String> info = {
        for (var info in category.findElements('info'))
          info.getAttribute('name')!: info.text
      };

      String? typeKey = firstWhereOrNull(
          info.keys, (key) => _typeTranslations.hasMatch(key.trim()));
      if (typeKey == null || !type.hasMatch(info[typeKey]!.trim())) {
        return;
      }

      var streamName = category.getAttribute('name');
      var streamNumber = int.tryParse(streamName!.split(' ').last);
      if (streamNumber == null) {
        return;
      }

      var codec = _getStreamInfoItem(info, _codecTranslations);
      var description = _getStreamInfoItem(info, _descriptionTranslations);
      var language = _getStreamInfoItem(info, _languageTranslations);

      String name = streamName;
      if (description != null && language != null) {
        if (description.startsWith(language)) {
          name = description;
        } else {
          name = '$description [$language]';
        }
      } else if (language != null) {
        name = language;
      } else if (description != null) {
        name = description;
      } else if (codec != null) {
        name = codec;
      }

      tracks.add(LanguageTrack(name, streamNumber));
    });
    tracks.sort((a, b) => a.streamNumber - b.streamNumber);
    return tracks;
  }

  String? _getStreamInfoItem(Map<String, String> info, RegExp name) {
    String? key =
        firstWhereOrNull(info.keys, (key) => name.hasMatch(key.trim()));
    return (key != null && info[key]!.isNotEmpty) ? info[key] : null;
  }

  @override
  String toString() {
    return 'VlcStatusResponse(${{
      'state': state,
      'time': time,
      'length': length,
      'volume': volume,
      'title': title,
      'fullscreen': fullscreen,
      'repeat': repeat,
      'random': random,
      'loop': loop,
      'currentPlId': currentPlId,
      'version': version,
      'audioTracks': audioTracks,
      'subtitleTracks': subtitleTracks,
    }})';
  }
}

class PlaylistItem {
  String id;
  String name;
  String uri;
  Duration duration;
  bool current;

  PlaylistItem.fromXmlElement(xml.XmlElement el)
      : name = el.getAttribute('name')!,
        id = el.getAttribute('id')!,
        duration = Duration(seconds: int.parse(el.getAttribute('duration')!)),
        uri = el.getAttribute('uri')!,
        current = el.getAttribute('current') != null;

  IconData get icon {
    if (isDir) {
      return Icons.folder;
    }
    if (isWeb) {
      return Icons.public;
    }
    if (isAudio) {
      return Icons.audiotrack;
    }
    if (isVideo) {
      return Icons.movie;
    }
    return Icons.insert_drive_file;
  }

  bool get isAudio => _audioExtensions.hasMatch(uri);

  bool get isDir => uri.startsWith('directory:');

  bool get isFile => uri.startsWith('file:');

  bool get isMedia => isAudio || isVideo || isWeb;

  bool get isVideo => _videoExtensions.hasMatch(uri);

  bool get isWeb => uri.startsWith('http');

  String get title => isVideo ? cleanVideoTitle(name, keepExt: false) : name;

  @override
  String toString() {
    return 'PlaylistItem(${{
      'name': name,
      'title': title,
      'id': id,
      'duration': duration,
      'uri': uri,
      'current': current
    }})';
  }
}

class VlcPlaylistResponse {
  List<PlaylistItem> items;
  PlaylistItem? currentItem;

  VlcPlaylistResponse.fromXmlDocument(xml.XmlDocument doc)
      : items = doc.rootElement
            .findElements('node')
            .first
            .findAllElements('leaf')
            .map((el) => PlaylistItem.fromXmlElement(el))
            .toList() {
    currentItem = firstWhereOrNull(items, (item) => item.current);
  }

  @override
  String toString() {
    return 'VlcPlaylistResponse(${{
      'items': items,
      'currentItem': currentItem
    }})';
  }
}
