import 'package:flutter/material.dart';

import 'utils.dart';

const emulatorLocalhost = '10.0.2.2';

const vlcHost = emulatorLocalhost;
const vlcPort = '8080';

var _videoExtensions = new RegExp(r'\.(avi|mkv|mp4)$');

var _episode = new RegExp(r's\d\de\d\d', caseSensitive: false);

// From https://en.wikipedia.org/wiki/Pirated_movie_release_types
var _source = [
  'ABC',
  'AMZN',
  'CBS',
  'CC',
  'CW',
  'DCU',
  'DSNY',
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
].map((s) => RegExp.escape(s)).join('|');

var _format = [
  'CAMRip',
  'CAM',
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

var _res = r'\d{3,4}p?';

var _movie = new RegExp(
  '\\.$_year(\\.$_res)?(\\.($_source))?\\.($_format)',
  caseSensitive: false,
);

String cleanTitle(String name, {bool keepExt = false}) {
  if (name == '') {
    return '';
  }
  if (_episode.hasMatch(name)) {
    return dotsToSpaces(name.substring(0, _episode.firstMatch(name).end));
  }
  if (_movie.hasMatch(name)) {
    return dotsToSpaces(name.substring(0, _movie.firstMatch(name).start));
  }
  return dotsToSpaces(name, keepExt: keepExt);
}

class BrowseItem {
  String type, name, path, uri;

  BrowseItem(
    this.type,
    this.name,
    this.path,
    this.uri,
  );

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

  IconData get icon {
    if (type == 'dir') {
      return Icons.folder;
    }

    if (isMovie) {
      return Icons.movie;
    }

    return Icons.insert_drive_file;
  }

  bool get isMovie => _videoExtensions.hasMatch(path);

  String get title => cleanTitle(name, keepExt: type == 'file');
}

class BrowseResult {
  BrowseItem item;
  List<BrowseItem> playlist;

  BrowseResult(this.item, this.playlist);
}
