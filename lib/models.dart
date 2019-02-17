import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils.dart';

const emulatorLocalhost = '10.0.2.2';

// TODO Remove once connection details are provided via Settings
const vlcHost = emulatorLocalhost;
const vlcPort = '8080';
const vlcPassword = 'vlcplayer';

var _videoExtensions = new RegExp(
    r'\.(3g2|3gp|3gp2|3gpp|amv|asf|avi|divx|drc|dv|f4v|flv|gvi|gxf|ismv|iso|m1v|m2v|m2t|m2ts|m4v|mkv|mov|mp2|mp2v|mp4|mp4v|mpe|mpeg|mpeg1|mpeg2|mpeg4|mpg|mpv2|mts|mtv|mxf|mxg|nsv|nut|nuv|ogm|ogv|ogx|ps|rec|rm|rmvb|tod|ts|tts|vob|vro|webm|wm|wmv|wtv|xesc)$');

var _audioExtensions = new RegExp(
    r'\.(3ga|a52|aac|ac3|adt|adts|aif|aifc|aiff|alac|amr|aob|ape|awb|caf|dts|flac|it|m4a|m4b|m4p|mid|mka|mlp|mod|mpa|mp1|mp2|mp3|mpc|mpga|oga|ogg|oma|opus|ra|ram|rmi|s3m|spx|tta|voc|vqf|w64|wav|wma|wv|xa|xm)$');

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

    if (isAudio) {
      return Icons.audiotrack;
    }

    if (isVideo) {
      return Icons.movie;
    }

    return Icons.insert_drive_file;
  }

  bool get isAudio => _audioExtensions.hasMatch(path);

  bool get isVideo => _videoExtensions.hasMatch(path);

  bool get isSupportedMedia => isAudio || isVideo;

  String get title => cleanTitle(name, keepExt: type == 'file');
}

class BrowseResult {
  BrowseItem item;
  List<BrowseItem> playlist;

  BrowseResult(this.item, this.playlist);
}

class Settings {
  SharedPreferences _prefs;

  bool dense;
  String ip;
  String port;
  String password;

  Settings(this._prefs) {
    Map<String, dynamic> json =
        jsonDecode(_prefs.getString('settings') ?? '{}');
    dense = json['dense'] ?? false;
    ip = vlcHost;
    port = json['port'] ?? vlcPort;
    password = json['password'] ?? vlcPassword;
  }

  Map<String, dynamic> toJson() => {
        'dense': dense,
        'ip': ip,
        'port': port,
        'password': password,
      };

  save() {
    _prefs.setString('settings', jsonEncode(this));
  }
}
