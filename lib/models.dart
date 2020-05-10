import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;

import 'utils.dart';

var _videoExtensions = RegExp(
    r'\.(3g2|3gp|3gp2|3gpp|amv|asf|avi|divx|drc|dv|f4v|flv|gvi|gxf|ismv|iso|m1v|m2v|m2t|m2ts|m4v|mkv|mov|mp2|mp2v|mp4|mp4v|mpe|mpeg|mpeg1|mpeg2|mpeg4|mpg|mpv2|mts|mtv|mxf|mxg|nsv|nut|nuv|ogm|ogv|ogx|ps|rec|rm|rmvb|tod|ts|tts|vob|vro|webm|wm|wmv|wtv|xesc)$');

var _audioExtensions = RegExp(
    r'\.(3ga|a52|aac|ac3|adt|adts|aif|aifc|aiff|alac|amr|aob|ape|awb|caf|dts|flac|it|m4a|m4b|m4p|mid|mka|mlp|mod|mpa|mp1|mp2|mp3|mpc|mpga|oga|ogg|oma|opus|ra|ram|rmi|s3m|spx|tta|voc|vqf|w64|wav|wma|wv|xa|xm)$');

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
        type = 'web';

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
    return Icons.insert_drive_file;
  }

  bool get isAudio => _audioExtensions.hasMatch(path);

  bool get isDir => type == 'dir';

  bool get isFile => type == 'file';

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

  bool blurredCoverBg;
  bool dense;
  Connection connection;

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

  String toString() {
    return '$name ($streamNumber)';
  }
}

class VlcStatusResponse {
  xml.XmlDocument document;
  List<LanguageTrack> _audioTracks;
  List<LanguageTrack> _subtitleTracks;
  Map<String, String> _info;

  VlcStatusResponse(this.document);

  String get state => document.findAllElements('state').first.text;

  Duration get time => Duration(
      seconds: int.tryParse(document.findAllElements('time').first.text));

  Duration get length => Duration(
      seconds: int.tryParse(document.findAllElements('length').first.text));

  int get volume => int.tryParse(document.findAllElements('volume').first.text);

  Map<String, String> get _metadata {
    if (this._info != null) {
      return _info;
    }
    var category = document.rootElement
        .findElements('information')
        .first
        ?.findElements('category')
        ?.first;
    _info = category != null
        ? Map.fromIterable(
            category.findElements('info'),
            key: (el) => el.getAttribute('name'),
            value: (el) => el.text,
          )
        : {};
    return _info;
  }

  String get title => _metadata['title'] ?? _metadata['filename'] ?? '';

  String get artist => _metadata['artist'] ?? '';

  String get artworkUrl => _metadata['artwork_url'];

  bool get fullscreen =>
      document.findAllElements('fullscreen').first.text == 'true';

  bool get repeat => document.findAllElements('repeat').first.text == 'true';

  bool get random => document.findAllElements('random').first.text == 'true';

  bool get loop => document.findAllElements('loop').first.text == 'true';

  String get currentPlId => document.findAllElements('currentplid').first.text;

  String get version => document.findAllElements('version').first.text;

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
        var language = info['Language'];
        if (language == null || language.isEmpty) {
          return;
        }
        var description = info['Description'];
        var name = language;
        if (description != null && description.isNotEmpty) {
          if (description.startsWith(language)) {
            name = description;
          } else {
            name = '$description [$language]';
          }
        }
        tracks.add(LanguageTrack(
            name, int.parse(category.getAttribute('name').split(' ').last)));
      }
    });
    tracks.sort((a, b) => a.streamNumber - b.streamNumber);
    return tracks;
  }

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
      : name = el.getAttribute('name'),
        id = el.getAttribute('id'),
        duration = Duration(seconds: int.tryParse(el.getAttribute('duration'))),
        uri = el.getAttribute('uri'),
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
  PlaylistItem currentItem;

  VlcPlaylistResponse.fromXmlDocument(xml.XmlDocument doc)
      : items = doc.rootElement
            .findElements('node')
            .first
            .findAllElements('leaf')
            .map((el) => PlaylistItem.fromXmlElement(el))
            .toList() {
    currentItem =
        items.firstWhere((item) => item.current ?? false, orElse: () => null);
  }

  String toString() {
    return 'VlcPlaylistResponse(${{
      'items': items,
      'currentItem': currentItem
    }})';
  }
}
