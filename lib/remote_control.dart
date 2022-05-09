import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:just_throttle_it/just_throttle_it.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:network_tools/network_tools.dart';
// import 'package:ping_discover_network/ping_discover_network.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:xml/xml.dart' as xml;

import 'equalizer_screen.dart';
import 'models.dart';
import 'open_media.dart';
import 'settings_screen.dart';
import 'utils.dart';
import 'vlc_configuration_guide.dart';
import 'widgets.dart';

var _headerFooterBgColor = const Color.fromRGBO(241, 241, 241, 1.0);
const _tickIntervalSeconds = 1;
const _sliderThrottleMilliseconds = 333;

enum _PopupMenuChoice {
  audioTrack,
  emptyPlaylist,
  fullscreen,
  playbackSpeed,
  settings,
  snapshot,
  subtitleTrack
}

class RemoteControl extends StatefulWidget {
  final SharedPreferences prefs;
  final Settings settings;

  const RemoteControl({
    Key? key,
    required this.prefs,
    required this.settings,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _RemoteControlState();
}

class _RemoteControlState extends State<RemoteControl> {
  //#region Setup state
  bool _autoConnecting = false;
  String? _autoConnectError;
  String? _autoConnectHost;
  //#endregion

  //#region HTTP requests / timer state
  final http.Client _client = http.Client();
  int? _lastStatusResponseCode;
  int? _lastPlaylistResponseCode;
  String? _lastPlaylistResponseBody;

  /// Timer which controls polling status and playlist info from VLC.
  late Timer _pollingTicker =
      Timer.periodic(const Duration(seconds: _tickIntervalSeconds), _tick);

  /// Timer used for single updates when polling is disabled.
  Timer? _singleUpdateTimer;
  //#endregion

  //#region VLC status state
  /// Contains subtitle and audio track information for use in the menu.
  VlcStatusResponse? _lastStatusResponse;

  /// Used to send equalizer changes to EqualizerScreen when it's open.
  final StreamController<Equalizer?> _equalizerController =
      StreamController<Equalizer?>.broadcast();

  // Fields populated from the latest VLC status response
  String _state = 'stopped';
  String _title = '';
  String _artist = '';
  Duration _time = Duration.zero;
  Duration _length = Duration.zero;
  int _volume = 256;
  double _rate = 1.0;
  bool _repeat = false;
  bool _loop = false;
  bool _random = false;
  Equalizer? _equalizer;

  /// Used to ignore status in any in-flight requests after we've told VLC to
  /// toggle playback settings.
  DateTime? _ignoreLoopStatusBefore;
  DateTime? _ignoreRandomStatusBefore;
  DateTime? _ignoreRateStatusBefore;
  //#endregion

  //#region Playlist state
  final ScrollController _scrollController = ScrollController();
  List<PlaylistItem> _playlist = [];
  PlaylistItem? _playing;
  String? _backgroundArtUrl;
  bool _reusingBackgroundArt = false;
  bool _showAddMediaButton = true;
  //#endregion

  //#region Volume state
  /// Controls sliding the volume controls in and out.
  bool _showVolumeControls = false;

  /// Set to true while volume controls are animating.
  bool _animatingVolumeControls = false;

  /// Set to true when the user is dragging the volume slider - used to ignore
  /// volume in status updates from VLC.
  bool _draggingVolume = false;

  /// Used to ignore volume status in any in-flight requests after we've told
  /// VLC to change the volume.
  DateTime? _ignoreVolumeStatusBefore;

  /// Previous volume when the volume button was long-pressed to mute.
  int? _preMuteVolume;

  /// Timer used for automatically hiding the volume controls after a delay.
  Timer? _hideVolumeControlsTimer;
  //#endregion

  //#region Time state
  /// Toggles between showing length and time left in the track timing section.
  bool _showTimeLeft = false;

  /// Set to true when the user is dragging the time slider - used to ignore
  /// time in status updates from VLC.
  bool _draggingTime = false;

  /// Set to true when the user is dragging the playback speed slider - used to
  /// ignore rate in status updates from VLC.
  bool _draggingRate = false;
  //#endregion

  @override
  initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _checkWifi();
  }

  @override
  dispose() {
    if (_pollingTicker.isActive) {
      _pollingTicker.cancel();
    }
    super.dispose();
  }

  //#region Connectivity
  _checkWifi() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.wifi) {
      _showWifiAlert(context);
    }
  }

  _showWifiAlert(BuildContext context) async {
    var subscription = Connectivity().onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.wifi) {
        Navigator.pop(context);
      }
    });
    await showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Turn on Wi-Fi'),
        content: Text(
          'A Wi-Fi connection was not detected.\n\nRemote Control for VLC needs to connect to your local network to control VLC.',
        ),
      ),
    );
    subscription.cancel();
  }
  //#endregion

  //#region HTTP requests
  get _authHeaders => {
        'Authorization': 'Basic ' +
            base64Encode(utf8.encode(':${widget.settings.connection.password}'))
      };

  String _artUrlForPlid(String plid) =>
      'http://${widget.settings.connection.authority}/art?item=$plid';

  /// Send a request to the named VLC API [endpoint] with any [queryParameters]
  /// given and return parsed response XML if successful.
  ///
  /// For the playlist endpoint, the response will be ignored if it's exactly
  /// the same as the last playlist response we received.
  Future<xml.XmlDocument?> _serverRequest(String endpoint,
      [Map<String, String>? queryParameters]) async {
    http.Response response;
    try {
      response = await _client
          .get(
            Uri.http(
              widget.settings.connection.authority,
              '/requests/$endpoint.xml',
              queryParameters,
            ),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 1));
    } catch (e) {
      assert(() {
        if (e is! TimeoutException) {
          print('_serverRequest error: $e');
        }
        return true;
      }());

      _resetPlaylist();

      setState(() {
        if (endpoint == 'status') {
          _lastStatusResponseCode = -1;
        } else if (endpoint == 'playlist') {
          _lastPlaylistResponseCode = -1;
          _lastPlaylistResponseBody = null;
        }
      });

      return null;
    }

    setState(() {
      if (endpoint == 'status') {
        _lastStatusResponseCode = response.statusCode;
      } else if (endpoint == 'playlist') {
        _lastPlaylistResponseCode = response.statusCode;
      }
    });

    if (response.statusCode != 200) {
      if (endpoint == 'playlist') {
        _lastPlaylistResponseBody = null;
      }
      return null;
    }

    var responseBody = utf8.decode(response.bodyBytes);
    if (endpoint == 'playlist') {
      if (responseBody == _lastPlaylistResponseBody) {
        return null;
      }
      _lastPlaylistResponseBody = responseBody;
    }
    return xml.XmlDocument.parse(responseBody);
  }

  Future<Equalizer?> _equalizerRequest(
      Map<String, String> queryParameters) async {
    xml.XmlDocument? document = await _serverRequest('status', queryParameters);
    if (document == null) {
      return null;
    }
    var equalizer = VlcStatusResponse(document).equalizer;
    assert(() {
      //print('$queryParameters => $equalizer');
      return true;
    }());
    return equalizer;
  }

  /// Send a request to VLC's status API endpoint - this is used to submit
  /// commands as well as getting the current state of VLC.
  _statusRequest([Map<String, String>? queryParameters]) async {
    var requestTime = DateTime.now();
    xml.XmlDocument? document = await _serverRequest('status', queryParameters);
    if (document == null) {
      _equalizerController.add(null);
      return;
    }

    var statusResponse = VlcStatusResponse(document);
    assert(() {
      if (queryParameters != null) {
        //print('VlcStatusRequest(${queryParameters ?? {}}) => $statusResponse');
      }
      return true;
    }());

    // State changes aren't reflected in commands which start and stop playback
    var ignoreStateUpdates = queryParameters != null &&
        (queryParameters['command'] == 'pl_play' ||
            queryParameters['command'] == 'pl_pause' ||
            queryParameters['command'] == 'pl_stop');

    // Volume changes aren't reflected in 'volume' command responses
    var ignoreVolumeUpdates = _draggingVolume ||
        queryParameters != null && queryParameters['command'] == 'volume' ||
        _ignoreVolumeStatusBefore != null &&
            requestTime.isBefore(_ignoreVolumeStatusBefore!);

    var ignoreRateUpdate = _draggingRate ||
        _ignoreRateStatusBefore != null &&
            requestTime.isBefore(_ignoreRateStatusBefore!);

    setState(() {
      if (!ignoreStateUpdates) {
        _state = statusResponse.state;
      }
      _length = statusResponse.length.isNegative
          ? Duration.zero
          : statusResponse.length;
      if (!ignoreVolumeUpdates) {
        _volume = statusResponse.volume.clamp(0, 512);
      }
      if (!ignoreRateUpdate) {
        _rate = statusResponse.rate;
      }
      // Keep the current title and artist when playback is stopped
      if (statusResponse.currentPlId != '-1') {
        _title = statusResponse.title;
        _artist = statusResponse.artist;
      }
      if (!_draggingTime) {
        var responseTime = statusResponse.time;
        // VLC will let time go over and under length using relative seek times
        // and will send the out-of-range time back to you before it corrects
        // itself.
        if (responseTime.isNegative) {
          _time = Duration.zero;
        } else if (responseTime > _length) {
          _time = _length;
        } else {
          _time = responseTime;
        }
      }
      // Set the background art URL when the current playlist item changes.
      // Keep the current URL when playback is stopped.
      if (statusResponse.currentPlId != '-1' &&
          statusResponse.currentPlId != _lastStatusResponse?.currentPlId) {
        // Keep using the existing URL if the new item has artwork and both
        // items are using the same artwork file.
        _reusingBackgroundArt = _backgroundArtUrl != null &&
            statusResponse.artworkUrl.isNotEmpty &&
            statusResponse.artworkUrl == _lastStatusResponse?.artworkUrl;
        if (statusResponse.artworkUrl.isNotEmpty && !_reusingBackgroundArt) {
          _backgroundArtUrl = _artUrlForPlid(statusResponse.currentPlId);
        } else if (statusResponse.artworkUrl.isEmpty) {
          _backgroundArtUrl = null;
        }
      }
      if (_ignoreLoopStatusBefore == null ||
          requestTime.isAfter(_ignoreLoopStatusBefore!)) {
        _loop = statusResponse.loop;
        _repeat = statusResponse.repeat;
      }
      if (_ignoreRandomStatusBefore == null ||
          requestTime.isAfter(_ignoreRandomStatusBefore!)) {
        _random = statusResponse.random;
      }
      _equalizer = statusResponse.equalizer;
      _equalizerController.add(_equalizer);
      _lastStatusResponse = statusResponse;
    });
  }

  /// Sends a request to VLC's playlist API endpoint to get the current playlist
  /// (which also indicates the currently playing item).
  _playlistRequest() async {
    xml.XmlDocument? document = await _serverRequest('playlist', null);

    if (document == null) {
      return;
    }

    var playlistResponse = VlcPlaylistResponse.fromXmlDocument(document);
    setState(() {
      // Clear current title and background URL if the playlist is cleared
      if (_playlist.isNotEmpty && playlistResponse.items.isEmpty) {
        _title = '';
        _backgroundArtUrl = '';
        _reusingBackgroundArt = false;
      }
      if (playlistResponse.items.length < _playlist.length) {
        SchedulerBinding.instance?.addPostFrameCallback((timeStamp) {
          _showAddMediaButtonIfNotScrollable();
        });
      }
      _playlist = playlistResponse.items;
      _playing = playlistResponse.currentItem;
    });
  }

  _updateStatusAndPlaylist() {
    if (!widget.settings.connection.hasIp) {
      _resetPlaylist();
      return;
    }

    _statusRequest();
    _playlistRequest();
  }

  /// Send a command with no arguments to VLC.
  ///
  /// If polling is disabled, also schedules an update to get the next status.
  _statusCommand(String command) {
    _statusRequest({'command': command});
    _scheduleSingleUpdate();
  }
  //#endregion

  //#region Polling and timers
  _tick(timer) async {
    _updateStatusAndPlaylist();
  }

  _togglePolling(context) {
    String message;
    if (_pollingTicker.isActive) {
      _pollingTicker.cancel();
      message = 'Paused polling for status updates';
    } else {
      _pollingTicker =
          Timer.periodic(const Duration(seconds: _tickIntervalSeconds), _tick);
      message = 'Resumed polling for status updates';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
    ));
    setState(() {});
  }

  _scheduleSingleUpdate() async {
    // Ticker will do the UI updates, no need to schedule any further update
    if (_pollingTicker.isActive) {
      return;
    }

    // Cancel any existing delay timer so the latest state is updated in one shot
    if (_singleUpdateTimer != null && _singleUpdateTimer!.isActive) {
      _singleUpdateTimer!.cancel();
    }

    _singleUpdateTimer = Timer(const Duration(seconds: _tickIntervalSeconds),
        _updateStatusAndPlaylist);
  }
  //#endregion

  //#region Setup
  _showConfigurationGuide() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VlcConfigurationGuide(),
      ),
    );
  }

  _autoConnect() async {
    setState(() {
      _autoConnecting = true;
      _autoConnectError = null;
      _autoConnectHost = null;
    });

    if (await Connectivity().checkConnectivity() != ConnectivityResult.wifi) {
      setState(() {
        _autoConnecting = false;
        _autoConnectError = 'Not connected to Wi-Fi';
      });
      return;
    }

    var ip = await NetworkInfo().getWifiIP();
    if (ip == null) {
      setState(() {
        _autoConnecting = false;
        _autoConnectError = 'Unable to get Wi-Fi IP address';
      });
      return;
    }

    var subnet = ip.substring(0, ip.lastIndexOf('.'));
    final stream = HostScanner.discoverPort(subnet, int.parse(defaultPort),
        timeout: const Duration(seconds: 1));

    List<String> ips = [];
    stream.listen((OpenPort port) {
      if (port.isOpen) {
        ips.add(port.ip);
      }
    }, onDone: () {
      if (ips.isEmpty) {
        setState(() {
          _autoConnecting = false;
          _autoConnectError =
              'Couldn\'t find any hosts running port 8080 on subnet $subnet';
        });
        return;
      }
      setState(() {
        if (ips.isNotEmpty) {
          _autoConnectHost =
              'Found multiple hosts, using the first one: ${ips.join(', ')}';
        }
        _autoConnectHost = 'Found host: ${ips.first}';
      });
      _testConnection(ips.first);
    }, onError: (error) {
      setState(() {
        _autoConnecting = false;
        _autoConnectError = 'Error scanning network: $error';
      });
    }, cancelOnError: true);
  }

  _testConnection(String ip) async {
    http.Response response;
    try {
      response = await http.get(
          Uri.http(
            '$ip:$defaultPort',
            '/requests/status.xml',
          ),
          headers: {
            'Authorization':
                'Basic ' + base64Encode(utf8.encode(':$defaultPassword'))
          }).timeout(const Duration(seconds: 1));
    } catch (e) {
      setState(() {
        _autoConnecting = false;
        if (e is TimeoutException) {
          _autoConnectError = 'Connection timed out';
        } else {
          _autoConnectError = 'Connection error: ${e.runtimeType}';
        }
      });
      return;
    }

    if (response.statusCode != 200) {
      setState(() {
        _autoConnecting = false;
        if (response.statusCode == 401) {
          _autoConnectError =
              'Default password was invalid – configure the connection manually.';
        } else {
          _autoConnectError =
              'Unexpected response: status code: ${response.statusCode}';
        }
      });
      return;
    }

    widget.settings.connection.ip = ip;
    widget.settings.connection.port = defaultPort;
    widget.settings.connection.password = defaultPassword;
    widget.settings.save();
    setState(() {
      _autoConnecting = false;
    });
  }

  _showSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          settings: widget.settings,
          onSettingsChanged: () {
            setState(() {
              widget.settings.save();
            });
          },
        ),
      ),
    );
  }
  //#endregion

  //#region Playlist
  _resetPlaylist() {
    _playing = null;
    _backgroundArtUrl = null;
    _reusingBackgroundArt = false;
    _playlist = [];
    _title = '';
    _showAddMediaButton = true;
  }

  _deletePlaylistItem(PlaylistItem item) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove item from playlist?'),
        content: Text(item.title),
        actions: <Widget>[
          TextButton(
            child: const Text("CANCEL"),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          TextButton(
            child: const Text("REMOVE"),
            onPressed: () {
              _statusRequest({
                'command': 'pl_delete',
                'id': item.id,
              });
              _scheduleSingleUpdate();
              Navigator.pop(context);
            },
          )
        ],
      ),
    );
  }
  //#endregion

  //#region Popup menu
  _onPopupMenuChoice(_PopupMenuChoice choice) {
    switch (choice) {
      case _PopupMenuChoice.audioTrack:
        _chooseAudioTrack();
        break;
      case _PopupMenuChoice.emptyPlaylist:
        _emptyPlaylist();
        break;
      case _PopupMenuChoice.fullscreen:
        _toggleFullScreen();
        break;
      case _PopupMenuChoice.playbackSpeed:
        _showPlaybackSpeedControl();
        break;
      case _PopupMenuChoice.settings:
        _showSettings();
        break;
      case _PopupMenuChoice.snapshot:
        _takeSnapshot();
        break;
      case _PopupMenuChoice.subtitleTrack:
        _chooseSubtitleTrack();
        break;
    }
  }

  Future<LanguageTrack?> _chooseLanguageTrack(List<LanguageTrack> options,
      {bool allowNone = false}) {
    var dialogOptions = options
        .map((option) => SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, option);
              },
              child: Text(option.name),
            ))
        .toList();
    if (allowNone) {
      dialogOptions.insert(
          0,
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context, LanguageTrack('(None)', -1));
            },
            child: const Text('(None)'),
          ));
    }
    return showDialog<LanguageTrack>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          children: dialogOptions,
        );
      },
    );
  }

  _chooseSubtitleTrack() async {
    if (_lastStatusResponse == null) {
      return;
    }
    LanguageTrack? subtitleTrack = await _chooseLanguageTrack(
        _lastStatusResponse!.subtitleTracks,
        allowNone: true);
    if (subtitleTrack != null) {
      _statusRequest({
        'command': 'subtitle_track',
        'val': subtitleTrack.streamNumber.toString(),
      });
    }
  }

  _chooseAudioTrack() async {
    if (_lastStatusResponse == null) {
      return;
    }
    LanguageTrack? audioTrack =
        await _chooseLanguageTrack(_lastStatusResponse!.audioTracks);
    if (audioTrack != null) {
      _statusRequest({
        'command': 'audio_track',
        'val': audioTrack.streamNumber.toString(),
      });
    }
  }

  _toggleEqualizer() {
    _statusRequest({
      'command': 'enableeq',
      'val': _equalizer?.enabled == true ? '0' : '1'
    });
    _scheduleSingleUpdate();
  }

  _showEqualizer() {
    if (_equalizer == null) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EqualizerScreen(
          equalizer: _equalizer!,
          equalizerStream: _equalizerController.stream,
          onToggleEnabled: (enabled) {
            return _equalizerRequest(
                {'command': 'enableeq', 'val': enabled ? '1' : '0'});
          },
          onPresetChange: (presetId) {
            return _equalizerRequest(
                {'command': 'setpreset', 'val': '$presetId'});
          },
          onPreampChange: (value) {
            return _equalizerRequest({'command': 'preamp', 'val': value});
          },
          onBandChange: (bandId, value) {
            return _equalizerRequest(
                {'command': 'equalizer', 'band': '$bandId', 'val': value});
          },
        ),
      ),
    );
  }

  _toggleFullScreen() {
    _statusCommand('fullscreen');
  }

  _emptyPlaylist() {
    _statusCommand('pl_empty');
  }

  _takeSnapshot() {
    _statusCommand('snapshot');
  }

  /// Convert the VLC playback [_rate] to a slider value between 0.0 and 1.0,
  /// where 0.25x → 0.0, 1.0x → 0.5 and 4.0x → 1.0.
  ///
  /// This matches the range of VLC's own playback rate slider, but it's
  /// possible for the rate to be set outside this range.
  double get _rateSliderValue {
    double value;
    if (_rate == 1.0) {
      value = 0.5;
    } else if (_rate < 1) {
      value = (_rate - 0.25) / 0.75 / 2;
    } else {
      value = 0.5 + ((_rate - 1) / 3.0 / 2);
    }
    return value.clamp(0.0, 1.0);
  }

  /// Convert a playback speed slider value between 0.0 and 1.0 to a VLC
  /// playback [_rate], where 0.0 → 0.25x, 0.5 -> 1.0x and 1.0 → 4.0x.
  ///
  /// This matches the range of VLC's own playback rate slider.
  double _sliderValueToRate(double value) {
    double rate;
    if (value == 0.5) {
      rate = 1.0;
    } else if (value < 0.5) {
      rate = 0.25 + (0.75 * value * 2);
    } else {
      rate = 1.0 + (3.0 * (value - 0.5) * 2);
    }
    return rate.clamp(0.25, 4.0);
  }

  _decrementRate(setState) {
    setState(() {
      _rate = math.max(0.25, ((_rate - 0.1) * 10.0).roundToDouble() / 10.0);
      _setRate(_rate);
    });
  }

  _incrementRate(setState) {
    setState(() {
      _rate = math.min(4.0, ((_rate + 0.1) * 10.0).roundToDouble() / 10.0);
      _setRate(_rate);
    });
  }

  _showPlaybackSpeedControl() {
    var theme = Theme.of(context);
    showModalBottomSheet(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      backgroundColor: Colors.white,
      isScrollControlled: true,
      context: context,
      builder: (builder) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Wrap(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 12, bottom: 8),
                  child: Text(
                    'Playback speed',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 20,
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                        child: Column(
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                const Text('0.25'),
                                Text(
                                  '${_rate.toStringAsFixed(2)}x',
                                  style: TextStyle(
                                    color: theme.primaryColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text('4.00')
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackShape: FullWidthTrackShape(),
                              ),
                              child: Slider(
                                value: _rateSliderValue,
                                onChangeStart: (value) {
                                  setState(() {
                                    _draggingRate = true;
                                  });
                                },
                                onChanged: (value) {
                                  setState(() {
                                    _rate = _sliderValueToRate(value);
                                  });
                                  Throttle.milliseconds(
                                      _sliderThrottleMilliseconds,
                                      _setRate,
                                      [_rate]);
                                },
                                onChangeEnd: (value) {
                                  _setRate(_rate);
                                  setState(() {
                                    _draggingRate = false;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(
                              right: 8, bottom: 4, left: 8),
                          child: ClipOval(
                            child: Material(
                              color: Colors.grey.shade200,
                              child: IconButton(
                                color: Colors.black,
                                icon: const Icon(Icons.keyboard_arrow_up),
                                onPressed: _rate < 4.0
                                    ? () {
                                        _incrementRate(setState);
                                      }
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              right: 8, top: 4, left: 8, bottom: 8),
                          child: ClipOval(
                            child: Material(
                              color: Colors.grey.shade200,
                              child: IconButton(
                                color: Colors.black,
                                icon: const Icon(Icons.keyboard_arrow_down),
                                onPressed: _rate > 0.25
                                    ? () {
                                        _decrementRate(setState);
                                      }
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                )
              ],
            );
          },
        );
      },
    );
  }
  //#endregion

  //#region Playlist
  bool get _showFab =>
      _lastStatusResponseCode == 200 &&
      _showAddMediaButton &&
      !_showVolumeControls &&
      !_animatingVolumeControls;

  /// Ensures the add media button is displayed if it's currently hidden and the
  /// playlist contents become non-scrollable.
  _showAddMediaButtonIfNotScrollable() {
    if (!_showAddMediaButton &&
        _scrollController.position.maxScrollExtent == 0.0) {
      setState(() {
        _showAddMediaButton = true;
      });
    }
  }

  /// Hides the add media button when scrolling down and re-displays it when
  /// scrolling back up again.
  _handleScroll() {
    switch (_scrollController.position.userScrollDirection) {
      case ScrollDirection.forward:
        if (_scrollController.position.maxScrollExtent !=
            _scrollController.position.minScrollExtent) {
          setState(() {
            _showAddMediaButton = true;
          });
        }
        break;
      case ScrollDirection.reverse:
        if (_scrollController.position.maxScrollExtent !=
            _scrollController.position.minScrollExtent) {
          setState(() {
            _showAddMediaButton = false;
          });
        }
        break;
      case ScrollDirection.idle:
        break;
    }
  }
  //#endregion

  //#region Volume control/slider
  double get _volumeSliderValue => _volume / volumeSliderScaleFactor;

  int _scaleVolumePercent(double percent) =>
      (percent * volumeSliderScaleFactor).round();

  _setVolumePercent(double percent, {bool finished = true}) {
    _ignoreVolumeStatusBefore = DateTime.now();
    // Preempt the expected volume
    setState(() {
      _volume = _scaleVolumePercent(percent);
    });
    _statusRequest({
      'command': 'volume',
      'val': '${_scaleVolumePercent(percent)}',
    });
    if (finished) {
      _scheduleSingleUpdate();
    }
  }

  _setVolumeRelative(int relativeValue) {
    // Nothing to do if already min or max
    if ((_volume <= 0 && relativeValue < 0) ||
        (_volume >= 512 && relativeValue > 0)) return;
    _ignoreVolumeStatusBefore = DateTime.now();
    // Preempt the expected volume
    setState(() {
      _volume = (_volume + relativeValue).clamp(0, 512);
      if (_volume == 0) {
        _preMuteVolume = null;
      }
    });
    _statusRequest({
      'command': 'volume',
      'val': '${relativeValue > 0 ? '+' : ''}$relativeValue',
    });
    _scheduleSingleUpdate();
  }

  _toggleVolumeControls([bool? show]) {
    show ??= !_showVolumeControls;
    setState(() {
      _showVolumeControls = show!;
      _animatingVolumeControls = true;
    });
    if (show == true) {
      _scheduleHidingVolumeControls();
    } else {
      _cancelHidingVolumeControls();
    }
  }

  _toggleMute() {
    if (_volume > 0) {
      _preMuteVolume = _volume;
      _setVolumePercent(0);
    } else {
      _setVolumePercent(_preMuteVolume != null
          ? _preMuteVolume! / volumeSliderScaleFactor
          : 100);
    }
    if (_showVolumeControls) {
      _scheduleHidingVolumeControls(2);
    }
  }

  _cancelHidingVolumeControls() {
    if (_hideVolumeControlsTimer != null &&
        _hideVolumeControlsTimer!.isActive) {
      _hideVolumeControlsTimer!.cancel();
      _hideVolumeControlsTimer = null;
    }
  }

  _scheduleHidingVolumeControls([int seconds = 4]) {
    _cancelHidingVolumeControls();
    _hideVolumeControlsTimer =
        Timer(Duration(seconds: seconds), () => _toggleVolumeControls(false));
  }
  //#endregion

  //#region Time/seek slider
  double get _seekSliderValue {
    if (_length.inSeconds == 0) {
      return 0.0;
    }
    return (_time.inSeconds / _length.inSeconds * 100);
  }

  _seekPercent(int percent) async {
    _statusRequest({
      'command': 'seek',
      'val': '$percent%',
    });
    _scheduleSingleUpdate();
  }

  _seekRelative(int seekTime) {
    _statusRequest({
      'command': 'seek',
      'val': '${seekTime > 0 ? '+' : ''}${seekTime}S',
    });
    _scheduleSingleUpdate();
  }

  _toggleShowTimeLeft() {
    setState(() {
      _showTimeLeft = !_showTimeLeft;
    });
  }
  //#endregion

  //#region Media controls
  _toggleLooping() {
    _ignoreLoopStatusBefore = DateTime.now();
    if (_repeat == false && _loop == false) {
      _statusCommand('pl_loop');
      setState(() {
        _loop = true;
      });
    } else if (_loop == true) {
      _statusCommand('pl_repeat');
      setState(() {
        _loop = false;
        _repeat = true;
      });
    } else if (_repeat == true) {
      _statusCommand('pl_repeat');
      setState(() {
        _loop = false;
        _repeat = false;
      });
    }
  }

  _toggleRandom() {
    _ignoreRandomStatusBefore = DateTime.now();
    _statusCommand('pl_random');
    setState(() {
      _random = !_random;
    });
  }

  _setRate(double rate) {
    _ignoreRateStatusBefore = DateTime.now();
    _statusRequest({
      'command': 'rate',
      'val': rate.toStringAsFixed(2),
    });
  }

  _stop() {
    _statusCommand('pl_stop');
  }

  _previous() {
    _statusCommand('pl_previous');
  }

  _play(PlaylistItem item) {
    _statusRequest({
      'command': 'pl_play',
      'id': item.id,
    });
    _scheduleSingleUpdate();
  }

  _pause() {
    // Preempt the expected state so the button feels more responsive
    setState(() {
      _state = (_state == 'playing' ? 'paused' : 'playing');
    });
    _statusCommand('pl_pause');
  }

  _next() {
    _statusCommand('pl_next');
  }

  _openMedia() async {
    BrowseResult? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OpenMedia(
          prefs: widget.prefs,
          settings: widget.settings,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    _statusRequest({
      'command':
          result.intent == BrowseResultIntent.play ? 'in_play' : 'in_enqueue',
      'input': result.item.playlistUri,
    });
    _scheduleSingleUpdate();
  }
  //#endregion

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Material(
              color: _headerFooterBgColor,
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 14),
                dense: widget.settings.dense,
                title: Text(
                  _playing == null && _title.isEmpty
                      ? 'Remote Control for VLC 1.5.0'
                      : _playing?.title ??
                          cleanVideoTitle(_title.split(RegExp(r'[\\/]')).last),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Visibility(
                      visible: !_pollingTicker.isActive,
                      child: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _updateStatusAndPlaylist,
                        tooltip: 'Refresh VLC status',
                      ),
                    ),
                    Visibility(
                      visible: _lastStatusResponseCode == 200,
                      child: GestureDetector(
                        onLongPress: _toggleEqualizer,
                        child: IconButton(
                          color: _equalizer?.enabled == true
                              ? theme.primaryColor
                              : null,
                          icon: const Icon(Icons.equalizer),
                          onPressed: _showEqualizer,
                        ),
                      ),
                    ),
                    Visibility(
                      visible: _lastStatusResponseCode == 200,
                      child: PopupMenuButton<_PopupMenuChoice>(
                        onSelected: _onPopupMenuChoice,
                        itemBuilder: (context) {
                          return [
                            PopupMenuItem(
                              child: ListTile(
                                dense: widget.settings.dense,
                                leading: const Icon(Icons.subtitles),
                                title: const Text('Subtitle track'),
                                enabled:
                                    (_lastStatusResponse?.subtitleTracks ?? [])
                                        .isNotEmpty,
                              ),
                              value: _PopupMenuChoice.subtitleTrack,
                              enabled:
                                  (_lastStatusResponse?.subtitleTracks ?? [])
                                      .isNotEmpty,
                            ),
                            PopupMenuItem(
                              child: ListTile(
                                dense: widget.settings.dense,
                                leading: const Icon(Icons.audiotrack),
                                title: const Text('Audio track'),
                                enabled:
                                    (_lastStatusResponse?.audioTracks ?? [])
                                            .length >
                                        1,
                              ),
                              value: _PopupMenuChoice.audioTrack,
                              enabled: (_lastStatusResponse?.audioTracks ?? [])
                                      .length >
                                  1,
                            ),
                            PopupMenuItem(
                              child: ListTile(
                                dense: widget.settings.dense,
                                leading: Icon(Icons.fullscreen,
                                    color: _lastStatusResponse != null &&
                                            _lastStatusResponse!.fullscreen
                                        ? theme.primaryColor
                                        : null),
                                title: const Text('Fullscreen'),
                                enabled: _playing != null &&
                                    (_playing!.isVideo || _playing!.isWeb),
                              ),
                              value: _PopupMenuChoice.fullscreen,
                              enabled: _playing != null &&
                                  (_playing!.isVideo || _playing!.isWeb),
                            ),
                            PopupMenuItem(
                              child: ListTile(
                                dense: widget.settings.dense,
                                leading: const Icon(Icons.image),
                                title: const Text('Take snapshot'),
                                enabled: _playing != null &&
                                    (_playing!.isVideo || _playing!.isWeb),
                              ),
                              value: _PopupMenuChoice.snapshot,
                              enabled: _playing != null &&
                                  (_playing!.isVideo || _playing!.isWeb),
                            ),
                            PopupMenuItem(
                              child: ListTile(
                                dense: widget.settings.dense,
                                leading: const Icon(Icons.directions_run),
                                title: const Text('Playback speed'),
                              ),
                              value: _PopupMenuChoice.playbackSpeed,
                            ),
                            PopupMenuItem(
                              child: ListTile(
                                dense: widget.settings.dense,
                                leading: const Icon(Icons.clear),
                                title: const Text('Clear playlist'),
                              ),
                              value: _PopupMenuChoice.emptyPlaylist,
                              enabled: _lastStatusResponse != null,
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              child: ListTile(
                                dense: widget.settings.dense,
                                leading: const Icon(Icons.settings),
                                title: Text(intl('Settings')),
                              ),
                              value: _PopupMenuChoice.settings,
                              enabled: _lastStatusResponse != null,
                            ),
                          ];
                        },
                      ),
                    )
                  ],
                ),
              ),
            ),
            const Divider(height: 0),
            _buildMainContent(),
            if (!_showVolumeControls && !_animatingVolumeControls)
              const Divider(height: 0),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final theme = Theme.of(context);
    final headingStyle = theme.textTheme.subtitle1!
        .copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor);
    if (!widget.settings.connection.hasIp) {
      return Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Remote Control for VLC Setup',
              style: theme.textTheme.headline5),
          const SizedBox(height: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('1. VLC configuration', style: headingStyle),
            const SizedBox(height: 8),
            const Text(
                'A step-by-step guide to enabling VLC\'s web interface for remote control:'),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                primary: theme.buttonTheme.colorScheme!.primary,
                onPrimary: Colors.white,
              ),
              onPressed: _showConfigurationGuide,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const <Widget>[
                  Icon(Icons.traffic),
                  SizedBox(width: 8.0),
                  Text('VLC Configuration Guide'),
                ],
              ),
            ),
          ]),
          const Divider(height: 48, color: Colors.black87),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('2. Automatic connection', style: headingStyle),
            const SizedBox(height: 8),
            const Text(
                'Once VLC is configured, scan your local network to try to connect automatically:'),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                primary: theme.buttonTheme.colorScheme!.primary,
                onPrimary: Colors.white,
              ),
              onPressed: !_autoConnecting ? _autoConnect : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  !_autoConnecting
                      ? const Icon(Icons.computer)
                      : const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                  const SizedBox(width: 8.0),
                  const Text('Scan Network for VLC'),
                ],
              ),
            ),
            if (_autoConnectHost != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: widget.settings.dense,
                leading: const Icon(
                  Icons.check,
                  color: Colors.green,
                ),
                title: Text(_autoConnectHost!),
              ),
            if (_autoConnectError != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: widget.settings.dense,
                leading: const Icon(
                  Icons.error,
                  color: Colors.redAccent,
                ),
                title: Text(_autoConnectError!),
              )
          ]),
          const Divider(height: 48, color: Colors.black87),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('3. Manual connection', style: headingStyle),
            const SizedBox(height: 8),
            const Text(
                'If automatic connection doesn\'t work, manually configure connection details:'),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                primary: theme.buttonTheme.colorScheme!.primary,
                onPrimary: Colors.white,
              ),
              onPressed: _showSettings,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const <Widget>[
                  Icon(Icons.settings),
                  SizedBox(width: 8.0),
                  Text('Configure VLC Connection'),
                ],
              ),
            )
          ]),
        ]),
      );
    }

    return Expanded(
      child: Stack(
        children: [
          if (widget.settings.blurredCoverBg &&
              _playing != null &&
              _playing!.isAudio &&
              _backgroundArtUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: .15,
                child: ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 2,
                      sigmaY: 2,
                    ),
                    child: _buildBackgroundImage(),
                  ),
                ),
              ),
            ),
          Scrollbar(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _playlist.length,
              itemBuilder: (context, index) {
                var item = _playlist[index];
                var icon = item.icon;
                if (item.current) {
                  switch (_state) {
                    case 'stopped':
                      icon = Icons.stop;
                      break;
                    case 'paused':
                      icon = Icons.pause;
                      break;
                    case 'playing':
                      icon = Icons.play_arrow;
                      break;
                  }
                }
                return ListTile(
                  dense: widget.settings.dense,
                  selected: item.current,
                  leading: Icon(icon),
                  title: Text(
                    item.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight:
                          item.current ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle:
                      item.current && _artist.isNotEmpty ? Text(_artist) : null,
                  trailing: !item.duration.isNegative
                      ? Text(formatTime(item.duration),
                          style: item.current
                              ? TextStyle(color: theme.primaryColor)
                              : null)
                      : null,
                  onTap: () {
                    if (item.current) {
                      _pause();
                    } else {
                      _play(item);
                    }
                  },
                  onLongPress: () {
                    _deletePlaylistItem(item);
                  },
                );
              },
            ),
          ),
          if (_playlist.isEmpty)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _lastPlaylistResponseCode == 200
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FractionallySizedBox(
                              widthFactor: 0.75,
                              child: Image.asset('assets/icon-512.png'),
                            ),
                            const SizedBox(height: 16),
                            Text(
                                'Connected to VLC ${_lastStatusResponse?.version}'),
                          ],
                        ),
                      )
                    : ConnectionAnimation(showSettings: _showSettings),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: _showFab ? 1 : 0),
              duration: const Duration(milliseconds: 250),
              curve: _showFab ? Curves.easeOut : Curves.easeIn,
              builder: (context, scale, child) => ScaleTransition(
                scale: AlwaysStoppedAnimation<double>(scale),
                child: FloatingActionButton(
                  child: const Icon(
                    Icons.eject,
                    color: Colors.white,
                  ),
                  onPressed: _openMedia,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Column(
              children: <Widget>[
                const Spacer(),
                TweenAnimationBuilder<Offset>(
                  tween: Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset(0, _showVolumeControls ? 0 : 1)),
                  duration: const Duration(milliseconds: 250),
                  curve: _showVolumeControls ? Curves.easeOut : Curves.easeIn,
                  onEnd: () {
                    setState(() {
                      _animatingVolumeControls = false;
                    });
                  },
                  builder: (context, offset, child) => SlideTransition(
                    position: AlwaysStoppedAnimation<Offset>(offset),
                    child: child,
                  ),
                  child: _buildVolumeControls(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundImage() {
    if (_reusingBackgroundArt) {
      return Image(
        image: NetworkImage(_backgroundArtUrl!, headers: _authHeaders),
        gaplessPlayback: true,
        fit: BoxFit.cover,
      );
    }
    return FadeInImage(
      imageErrorBuilder: (_, __, ___) => const SizedBox(),
      placeholder: MemoryImage(kTransparentImage),
      image: NetworkImage(_backgroundArtUrl!, headers: _authHeaders),
      fit: BoxFit.cover,
    );
  }

  Widget _buildVolumeControls() {
    return Column(
      children: <Widget>[
        const Divider(height: 0),
        Container(
          color: _headerFooterBgColor,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: Colors.transparent,
            child: Row(
              children: <Widget>[
                // Volume down
                IconButton(
                  icon: const Icon(Icons.remove),
                  tooltip: 'Decrease volume',
                  onPressed: _volume > 0
                      ? () {
                          if (!_showVolumeControls) {
                            _showVolumeControls = true;
                          }
                          _setVolumeRelative(-25);
                          _scheduleHidingVolumeControls(2);
                        }
                      : null,
                ),
                // Volume slider
                Expanded(
                  flex: 1,
                  child: Slider(
                    label: '${_volumeSliderValue.round()}%',
                    divisions: 200,
                    max: 200,
                    value: _volumeSliderValue,
                    onChangeStart: (percent) {
                      setState(() {
                        _draggingVolume = true;
                        if (!_showVolumeControls) {
                          _showVolumeControls = true;
                        }
                      });
                      _cancelHidingVolumeControls();
                    },
                    onChanged: (percent) {
                      setState(() {
                        _volume = _scaleVolumePercent(percent);
                      });
                      Throttle.milliseconds(_sliderThrottleMilliseconds,
                          _setVolumePercent, [percent], {#finished: false});
                    },
                    onChangeEnd: (percent) {
                      _setVolumePercent(percent);
                      if (percent == 0.0) {
                        _preMuteVolume = null;
                      }
                      setState(() {
                        _draggingVolume = false;
                      });
                      _scheduleHidingVolumeControls(2);
                    },
                  ),
                ),
                // Volume up
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Increase volume',
                  onPressed: _volume < 512
                      ? () {
                          if (!_showVolumeControls) {
                            _showVolumeControls = true;
                          }
                          _setVolumeRelative(25);
                          _scheduleHidingVolumeControls(2);
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    var theme = Theme.of(context);
    return Visibility(
      visible:
          widget.settings.connection.isValid && _lastStatusResponseCode == 200,
      child: Container(
        color: _headerFooterBgColor,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () {
                        _togglePolling(context);
                      },
                      child: Text(
                        _state != 'stopped' ? formatTime(_time) : '––:––',
                        style: TextStyle(
                          color: _pollingTicker.isActive
                              ? theme.textTheme.bodyText2!.color
                              : theme.disabledColor,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      divisions: 100,
                      max: _state != 'stopped' ? 100 : 0,
                      value: _seekSliderValue,
                      onChangeStart: (percent) {
                        setState(() {
                          _draggingTime = true;
                        });
                      },
                      onChanged: (percent) {
                        setState(() {
                          _time = Duration(
                            seconds:
                                (_length.inSeconds / 100 * percent).round(),
                          );
                        });
                      },
                      onChangeEnd: (percent) async {
                        await _seekPercent(percent.round());
                        setState(() {
                          _draggingTime = false;
                        });
                      },
                    ),
                  ),
                  GestureDetector(
                    onTap: _toggleShowTimeLeft,
                    child: Text(
                      _state != 'stopped' && _length != Duration.zero
                          ? _showTimeLeft
                              ? '-' + formatTime(_length - _time)
                              : formatTime(_length)
                          : '––:––',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: _toggleVolumeControls,
                      onLongPress: _toggleMute,
                      child: Icon(
                        _volume == 0
                            ? Icons.volume_off
                            : _volume < 102
                                ? Icons.volume_mute
                                : _volume < 218
                                    ? Icons.volume_down
                                    : Icons.volume_up,
                        color: Colors.black,
                      ),
                    ),
                  )
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.only(left: 9, right: 9, bottom: 6, top: 3),
              child: Row(
                // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  GestureDetector(
                    child: Icon(
                      _repeat ? Icons.repeat_one : Icons.repeat,
                      color: _repeat || _loop
                          ? theme.primaryColor
                          : theme.disabledColor,
                      size: 30,
                    ),
                    onTap: _toggleLooping,
                  ),
                  const Expanded(child: VerticalDivider()),
                  GestureDetector(
                    child: const Icon(
                      Icons.skip_previous,
                      color: Colors.black,
                      size: 30,
                    ),
                    onTap: _previous,
                  ),
                  const Expanded(child: VerticalDivider()),
                  // Rewind button
                  GestureDetector(
                    child: const Icon(
                      Icons.fast_rewind,
                      color: Colors.black,
                      size: 30,
                    ),
                    onTap: () {
                      _seekRelative(-10);
                    },
                  ),
                  // Play/pause button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: GestureDetector(
                      onTap: _pause,
                      onLongPress: _stop,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                            begin: 0.0,
                            end: _state == 'paused' || _state == 'stopped'
                                ? 0.0
                                : 1.0),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        builder: (context, progress, child) => AnimatedIcon(
                          color: Colors.black,
                          size: 42,
                          icon: AnimatedIcons.play_pause,
                          progress: AlwaysStoppedAnimation<double>(progress),
                        ),
                      ),
                    ),
                  ),
                  // Fast forward
                  GestureDetector(
                    child: const Icon(
                      Icons.fast_forward,
                      color: Colors.black,
                      size: 30,
                    ),
                    onTap: () {
                      _seekRelative(10);
                    },
                  ),
                  const Expanded(child: VerticalDivider()),
                  GestureDetector(
                    child: const Icon(
                      Icons.skip_next,
                      color: Colors.black,
                      size: 30,
                    ),
                    onTap: _next,
                  ),
                  const Expanded(child: VerticalDivider()),
                  GestureDetector(
                    child: Icon(
                      Icons.shuffle,
                      color: _random ? theme.primaryColor : theme.disabledColor,
                      size: 30,
                    ),
                    onTap: _toggleRandom,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class ConnectionAnimation extends StatefulWidget {
  final VoidCallback showSettings;

  const ConnectionAnimation({Key? key, required this.showSettings})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _ConnectionAnimationState();
}

class _ConnectionAnimationState extends State<ConnectionAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat();

  late final Animation<int> _animation =
      IntTween(begin: 0, end: 3).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  ));

  @override
  dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: AlignmentDirectional.center,
            children: <Widget>[
              FractionallySizedBox(
                widthFactor: 0.75,
                child: Image.asset('assets/cone.png'),
              ),
              AnimatedBuilder(
                animation: _animation,
                builder: (BuildContext context, Widget? child) {
                  return FractionallySizedBox(
                    widthFactor: 0.75,
                    child: Image.asset(
                      'assets/signal-${_animation.value}.png',
                    ),
                  );
                },
              )
            ],
          ),
          const SizedBox(height: 16),
          const Text('Trying to connect to VLC…'),
          const SizedBox(height: 16),
          IconButton(
            color: theme.textTheme.caption!.color,
            iconSize: 48,
            icon: const Icon(Icons.settings),
            onPressed: widget.showSettings,
          )
        ],
      ),
    );
  }
}
