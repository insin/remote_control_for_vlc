import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;

import 'utils.dart';

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

  IconData get icon {
    if (isDir) {
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

  bool get isDir => type == 'dir';

  bool get isFile => type == 'file';

  bool get isVideo => _videoExtensions.hasMatch(path);

  bool get isSupportedMedia => isAudio || isVideo;

  String get title => cleanTitle(name, keepExt: isFile);

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

  String toString() => 'BrowseItem(${toJson()})';
}

class BrowseResult {
  BrowseItem item;
  List<BrowseItem> playlist;

  BrowseResult(this.item, this.playlist);
}

// ignore: unused_element
const _emulatorLocalhost = '10.0.2.2';

const _defaultPort = '8080';
const _defaultPassword = 'vlcplayer';

var _ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
var _numericPattern = RegExp(r'^\d+$');

class Connection {
  String _ip;
  String _port;
  String _password;

  String _ipError;
  String _portError;
  String _passwordError;

  Connection();

  get ip => _ip;
  get port => _port;
  get password => _password;
  get ipError => _ipError;
  get portError => _portError;
  get passwordError => _passwordError;

  String get authority => '$_ip:$_port';

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
    port = json['port'] ?? _defaultPort;
    password = json['password'] ?? _defaultPassword;
  }

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'password': password,
      };
}

class Settings {
  SharedPreferences _prefs;

  bool dense;
  Connection connection;

  Settings(this._prefs) {
    Map<String, dynamic> json =
        jsonDecode(_prefs.getString('settings') ?? '{}');
    dense = json['dense'] ?? false;
    connection = Connection.fromJson(json['connection'] ?? {});
  }

  Map<String, dynamic> toJson() => {
        'dense': dense,
        'connection': connection,
      };

  save() {
    _prefs.setString('settings', jsonEncode(this));
  }
}

class LanguageTrack {
  String language;
  int streamNumber;

  LanguageTrack(this.language, this.streamNumber);

  String toString() {
    return '$language ($streamNumber)';
  }
}

class VlcStatusResponse {
  xml.XmlDocument document;
  List<LanguageTrack> _audioTracks;
  List<LanguageTrack> _subtitleTracks;

  VlcStatusResponse(this.document);

  String get state => document.findAllElements('state').first.text;

  Duration get time => Duration(
      seconds: int.tryParse(document.findAllElements('time').first.text));

  Duration get length => Duration(
      seconds: int.tryParse(document.findAllElements('length').first.text));

  String get title {
    Map<String, String> titles = Map.fromIterable(
      document.findAllElements('info').where(
          (el) => ['title', 'filename'].contains(el.getAttribute('name'))),
      key: (el) => el.getAttribute('name'),
      value: (el) => el.text,
    );
    return titles['title'] ?? titles['filename'] ?? '';
  }

  bool get fullscreen =>
      document.findAllElements('fullscreen').first.text == 'true';

  List<LanguageTrack> get audioTracks {
    if (_audioTracks == null) {
      _audioTracks = _getLanguageTracks('Audio');
    }
    return _audioTracks;
  }

  List<LanguageTrack> get subtitleTracks {
    if (_subtitleTracks == null) {
      _subtitleTracks = _getLanguageTracks('Subtitle');
    }
    return _subtitleTracks;
  }

  List<LanguageTrack> _getLanguageTracks(String type) {
    List<LanguageTrack> tracks = [];
    document.findAllElements('category').forEach((category) {
      Map<String, String> info = Map.fromIterable(category.findElements('info'),
          key: (info) => info.getAttribute('name'), value: (info) => info.text);
      if (info['Type'] == type) {
        tracks.add(new LanguageTrack(info['Language'],
            int.parse(category.getAttribute('name').split(' ').last)));
      }
    });
    tracks.sort((a, b) => a.streamNumber - b.streamNumber);
    return tracks;
  }

  String toString() {
    return 'VlcResponse(${{
      'state': state,
      'time': time,
      'length': length,
      'title': title,
      'fullscreen': fullscreen,
      'audioTracks': audioTracks,
      'subtitleTracks': subtitleTracks,
    }})';
  }
}
