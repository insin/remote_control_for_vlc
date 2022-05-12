var _dot = RegExp(r'\.');

var _episode = RegExp(r's\d\de\d\d', caseSensitive: false);

// From https://en.wikipedia.org/wiki/Pirated_movie_release_types#Common_abbreviations
var _source = [
  'ABC',
  'ATVP',
  'AMZN',
  'BBC',
  'CBS',
  'CC',
  'CR',
  'CW',
  'DCU',
  'DSNY',
  'FBWatch',
  'FREE',
  'FOX',
  'HULU',
  'iP',
  'LIFE',
  'MTV',
  'NBC',
  'NICK',
  'NF',
  'RED',
  'TF1',
  'STZ',
].map((s) => RegExp.escape(s)).join('|');

// From https://en.wikipedia.org/wiki/Pirated_movie_release_types#Release_formats
var _format = [
  'CAMRip',
  'CAM',
  'HDCAM',
  'TS',
  'HDTS',
  'TELESYNC',
  'PDVD',
  'PreDVDRip',
  'WP',
  'WORKPRINT',
  'TC',
  'HDTC',
  'TELECINE',
  'PPV',
  'PPVRip',
  'SCR',
  'SCREENER',
  'DVDSCR',
  'DVDSCREENER',
  'BDSCR',
  'DDC',
  'R5',
  'R5.LINE',
  'R5.AC3.5.1.HQ',
  'DVDRip',
  'DVDMux',
  'DVDR',
  'DVD-Full',
  'Full-Rip',
  'ISO rip',
  'lossless rip',
  'untouched rip',
  'DVD-5',
  'DVD-9',
  'DSR',
  'DSRip',
  'SATRip',
  'DTHRip',
  'DVBRip',
  'HDTV',
  'PDTV',
  'DTVRip',
  'TVRip',
  'HDTVRip',
  'VODRip',
  'VODR',
  'WEBDL',
  'WEB DL',
  'WEB-DL',
  'HDRip',
  'WEB-DLRip',
  'WEBRip',
  'WEB Rip',
  'WEB-Rip',
  'WEB',
  'WEB-Cap',
  'WEBCAP',
  'WEB Cap',
  'HC',
  'HD-Rip',
  'Blu-Ray',
  'BluRay',
  'BDRip',
  'BRip',
  'BRRip',
  'BDMV',
  'BDR',
  'BD25',
  'BD50',
  'BD5',
  'BD9',
].map((s) => RegExp.escape(s)).join('|');

var _year = r'\d{4}';

// 720p, 1080p etc.
var _res = r'\d{3,4}p?';

// DUBBED, JAPANESE, INDONESIAN etc.
var _language = r'[A-Z]+';

var _movie = RegExp(
  '\\.$_year(\\.$_language)?(\\.$_res)?(\\.($_source))?\\.($_format)',
  caseSensitive: false,
);

String cleanVideoTitle(String name, {bool keepExt = false}) {
  if (name == '') {
    return '';
  }
  if (_episode.hasMatch(name)) {
    return dotsToSpaces(name.substring(0, _episode.firstMatch(name)!.end));
  }
  if (_movie.hasMatch(name)) {
    return dotsToSpaces(name.substring(0, _movie.firstMatch(name)!.start));
  }
  return dotsToSpaces(name, keepExt: keepExt);
}

String dotsToSpaces(String s, {bool keepExt = false}) {
  String ext = '';
  var parts = s.split(_dot);
  if (keepExt) {
    ext = parts.removeLast();
  }
  return '${parts.join(' ')}.$ext';
}

/// [Iterable.firstWhere] doesn't work with null safety when you want to fall
/// back to returning `null`.
///
/// See https://github.com/dart-lang/sdk/issues/42947
T? firstWhereOrNull<T>(Iterable<T> iterable, bool Function(T element) test) {
  for (var element in iterable) {
    if (test(element)) return element;
  }
  return null;
}

String formatTime(Duration duration) {
  String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '${duration.inHours >= 1 ? '${duration.inHours}:' : ''}$minutes:$seconds';
}

/// Matches some of the protocols supported by VLC.
var urlRegExp = RegExp(r'((f|ht)tps?|mms|rts?p)://');

/*
 * Trick stolen from https://gist.github.com/shubhamjain/9809108#file-vlc_http-L108
 * The interface expects value between 0 and 512 while in the UI it is 0% to 200%.
 * So a factor of 2.56 is used to convert 0% to 200% to a scale of 0 to 512.
 */
const volumeSliderScaleFactor = 2.56;
