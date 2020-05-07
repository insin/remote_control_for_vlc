import 'dart:async';
import 'dart:convert';

import 'package:connectivity/connectivity.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_throttle_it/just_throttle_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;

import 'models.dart';
import 'open_media.dart';
import 'settings_screen.dart';
import 'utils.dart';

var _headerFooterBgColor = Color.fromRGBO(241, 241, 241, 1.0);
const _volumeSlidingThrottleMilliseconds = 333;

enum PopupMenuChoice {
  AUDIO_TRACK,
  FULLSCREEN,
  SUBTITLE_TRACK,
  RANDOM_PLAY,
  REPEAT,
  LOOP,
  EMPTY_PLAYLIST
}

class RemoteControl extends StatefulWidget {
  final SharedPreferences prefs;
  final Settings settings;

  RemoteControl({
    @required this.prefs,
    @required this.settings,
  });

  @override
  State<StatefulWidget> createState() => _RemoteControlState();
}

class _RemoteControlState extends State<RemoteControl> {
  http.Client client = http.Client();
  int lastStatusResponseCode;
  int lastPlaylistResponseCode;
  VlcStatusResponse lastStatusResponse;
  VlcPlaylistResponse lastPlaylistResponse;
  String state = 'stopped';
  String title = '';
  Duration time = Duration.zero;
  Duration length = Duration.zero;

  Timer ticker;
  Timer delayedTimer;
  static const _tickIntervalSecs = 1;
  bool showTimeLeft = false;
  bool sliding = false;

  int _volume = 256;
  int _preMuteVolume;
  bool _volumeSliding = false;
  DateTime _ignoreVolumeUpdatesBefore;
  bool _showVolumeControls = false;
  bool _animatingVolumeControls = false;
  Timer _hideVolumeControlsTimer;

  List<PlaylistItem> playlist;
  PlaylistItem playing;
  String currentPlId;

  @override
  initState() {
    ticker = Timer.periodic(Duration(seconds: _tickIntervalSecs), _tick);
    super.initState();
    _checkWifi();
  }

  @override
  dispose() {
    if (ticker.isActive) {
      ticker.cancel();
    }
    super.dispose();
  }

  Future<VlcStatusResponse> _statusRequest(
      [Map<String, String> queryParameters]) async {
    assert(() {
      print('VlcStatusRequest(${queryParameters ?? {}})');
      return true;
    }());
    var requestTime = DateTime.now();
    xml.XmlDocument document = await _serverRequest('status', queryParameters);
    if (document == null) {
      return null;
    }
    var statusResponse = VlcStatusResponse(document);
    assert(() {
      print('${queryParameters ?? {}} response: $statusResponse');
      return true;
    }());

    // State changes aren't reflected in commands which start and stop playback
    var ignoreStateUpdates = queryParameters != null &&
        (queryParameters['command'] == 'pl_play' ||
            queryParameters['command'] == 'pl_pause' ||
            queryParameters['command'] == 'pl_stop');

    var ignoreVolumeUpdates = _volumeSliding ||
        // Volume changes aren't reflected in 'volume' command responses
        queryParameters != null && queryParameters['command'] == 'volume' ||
        _ignoreVolumeUpdatesBefore != null &&
            requestTime.isBefore(_ignoreVolumeUpdatesBefore);

    setState(() {
      if (!ignoreStateUpdates) {
        state = statusResponse.state;
      }
      length = statusResponse.length;
      if (!ignoreVolumeUpdates && statusResponse.volume != null) {
        _volume = statusResponse.volume.clamp(0, 512);
      }
      title = statusResponse.title;
      currentPlId = statusResponse.currentPlId;
      if (!sliding) {
        var responseTime = statusResponse.time;
        // VLC will let time go over and under length using relative seek times
        // and will send the out-of-range time back to you before it corrects
        // itself.
        if (responseTime.isNegative) {
          time = Duration.zero;
        } else if (responseTime > length) {
          time = length;
        } else {
          time = responseTime;
        }
      }
      lastStatusResponse = statusResponse;
    });

    return statusResponse;
  }

  Future<VlcPlaylistResponse> _playlistRequest() async {
    assert(() {
      //print('VlcPlaylistRequest()');
      return true;
    }());
    xml.XmlDocument document = await _serverRequest('playlist', null);
    if (document == null) {
      return null;
    }
    var playlistResponse = VlcPlaylistResponse(document);
    assert(() {
      //print(playlistResponse);
      return true;
    }());
    setState(() {
      playlist = playlistResponse.playListItems;
      playing = playlistResponse.currentItem;
      lastPlaylistResponse = lastPlaylistResponse;
    });
    return playlistResponse;
  }

  Future<xml.XmlDocument> _serverRequest(String requestType,
      [Map<String, String> queryParameters]) async {
    http.Response response;
    try {
      response = await client.get(
        Uri.http(
          widget.settings.connection.authority,
          '/requests/$requestType.xml',
          queryParameters,
        ),
        headers: {
          'Authorization': 'Basic ' +
              base64Encode(
                  utf8.encode(':${widget.settings.connection.password}')),
        },
      ).timeout(Duration(seconds: 1));
    } catch (e) {
      _resetPlaylist();
      assert(() {
        print('Error: ${e.runtimeType}');
        return true;
      }());
    }
    setState(() {
      if (requestType == 'status') {
        lastStatusResponseCode = response?.statusCode ?? -1;
      } else if (requestType == 'playlist') {
        lastPlaylistResponseCode = response?.statusCode ?? -1;
      }
    });
    if (response?.statusCode == 200) {
      return xml.parse(utf8.decode(response.bodyBytes));
    }
    return null;
  }

  _togglePolling(context) {
    String message;
    if (ticker.isActive) {
      ticker.cancel();
      message = 'Paused polling for status updates';
    } else {
      ticker = Timer.periodic(Duration(seconds: _tickIntervalSecs), _tick);
      message = 'Resumed polling for status updates';
    }
    Scaffold.of(context).showSnackBar(SnackBar(
      content: Text(message),
    ));
    setState(() {});
  }

  _checkWifi() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.wifi) {
      _showWifiAlert(context);
    }
  }

  void _showWifiAlert(BuildContext context) async {
    var subscription = Connectivity().onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.wifi) {
        Navigator.pop(context);
      }
    });
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Turn on Wi-Fi'),
        content: Text(
          'A Wi-Fi connection was not detected.\n\nVLC Remote needs to connect to your local network to control VLC.',
        ),
      ),
    );
    subscription.cancel();
  }

  _tick(timer) async {
    _updateStateAndPlaylist();
  }

  _scheduleSingleUpdate() async {
    // Ticker will do the UI updates, no need to schedule any further update
    if (ticker != null && ticker.isActive) {
      return;
    }

    // Cancel any existing delay timer so the latest state is updated in one shot
    if (delayedTimer != null && delayedTimer.isActive) {
      delayedTimer.cancel();
    }

    delayedTimer =
        Timer(Duration(seconds: _tickIntervalSecs), _updateStateAndPlaylist);
  }

  _resetPlaylist() {
    playing = null;
    playlist = null;
    title = '';
  }

  _updateStateAndPlaylist() {
    if (widget.settings.connection.isNotValid) {
      _resetPlaylist();
      return;
    }

    _statusRequest();
    _playlistRequest();
  }

  _openMedia() async {
    BrowseResult result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => OpenMedia(
                prefs: widget.prefs,
                settings: widget.settings,
              )),
    );

    if (result != null) {
      var response = await _statusRequest({
        'command': 'in_play',
        'input': result.item.uri,
      });
      if (response == null) {
        return;
      }
      assert(() {
        print('Playing ${result.item}');
        return true;
      }());
    }
  }

  _enqueueMedia() async {
    BrowseResult result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => OpenMedia(
                prefs: widget.prefs,
                settings: widget.settings,
              )),
    );

    if (result != null) {
      var response = await _statusRequest({
        'command': 'in_enqueue',
        'input': result.item.uri,
      });
      _scheduleSingleUpdate();
      if (response == null) {
        return;
      }
      assert(() {
        print('Enqueued ${result.item}');
        return true;
      }());
    }
  }

  _play(PlaylistItem item) {
    // Preempt setting active playlist item
    if (playing != item) {
      playing = item;
    }
    _statusRequest({
      'command': 'pl_play',
      'id': item.id,
    });
    _scheduleSingleUpdate();
  }

  _previous() {
    _statusRequest({'command': 'pl_previous'});
    _scheduleSingleUpdate();
  }

  _next() {
    _statusRequest({'command': 'pl_next'});
    _scheduleSingleUpdate();
  }

  _delete(PlaylistItem item) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Remove item from playlist?'),
          content: Text(item.title),
          actions: <Widget>[
            FlatButton(
              child: Text("CANCEL"),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            FlatButton(
              child: Text("REMOVE"),
              autofocus: true,
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
        );
      },
    );
  }

  _emptyPlaylist() {
    _statusRequest({'command': 'pl_empty'});
    _scheduleSingleUpdate();
  }

  _toggleRandom() {
    _statusRequest({'command': 'pl_random'});
    _scheduleSingleUpdate();
  }

  _toggleRepeat() {
    _statusRequest({'command': 'pl_repeat'});
    _scheduleSingleUpdate();
  }

  _toggleLoop() {
    _statusRequest({'command': 'pl_loop'});
    _scheduleSingleUpdate();
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

  int _scaleVolumePercent(double percent) =>
      (percent * volumeSliderScaleFactor).round();

  _volumePercent(double percent, {bool finished = true}) {
    _ignoreVolumeUpdatesBefore = DateTime.now();
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

  _volumeRelative(int relativeValue) {
    // Nothing to do if already min or max
    if ((_volume <= 0 && relativeValue < 0) ||
        (_volume >= 512 && relativeValue > 0)) return;
    _ignoreVolumeUpdatesBefore = DateTime.now();
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

  _pause() {
    // Preempt the expected state so the button feels more responsive
    setState(() {
      state = (state == 'playing' ? 'paused' : 'playing');
    });
    _statusRequest({
      'command': 'pl_pause',
    });
    _scheduleSingleUpdate();
  }

  _stop() {
    _statusRequest({'command': 'pl_stop'});
    _scheduleSingleUpdate();
  }

  double _volumeSliderValue() {
    return _volume / volumeSliderScaleFactor;
  }

  double _sliderValue() {
    if (length.inSeconds == 0) {
      return 0.0;
    }
    return (time.inSeconds / length.inSeconds * 100);
  }

  Future<LanguageTrack> _chooseLanguageTrack(List<LanguageTrack> options) {
    return showDialog<LanguageTrack>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          children: options
              .map((option) => SimpleDialogOption(
                    onPressed: () {
                      Navigator.pop(context, option);
                    },
                    child: Text(option.name),
                  ))
              .toList(),
        );
      },
    );
  }

  void _chooseSubtitleTrack() async {
    LanguageTrack subtitleTrack =
        await _chooseLanguageTrack(lastStatusResponse.subtitleTracks);
    if (subtitleTrack != null) {
      _statusRequest({
        'command': 'subtitle_track',
        'val': subtitleTrack.streamNumber.toString(),
      });
    }
  }

  void _chooseAudioTrack() async {
    LanguageTrack audioTrack =
        await _chooseLanguageTrack(lastStatusResponse.audioTracks);
    if (audioTrack != null) {
      _statusRequest({
        'command': 'audio_track',
        'val': audioTrack.streamNumber.toString(),
      });
    }
  }

  void _toggleFullScreen() {
    _statusRequest({
      'command': 'fullscreen',
    });
  }

  void _toggleVolumeControls([bool show]) {
    if (show == null) {
      show = !_showVolumeControls;
    }
    setState(() {
      _showVolumeControls = show;
      _animatingVolumeControls = true;
    });
    if (show == true) {
      _scheduleHidingVolumeControls();
    } else {
      _cancelHidingVolumeControls();
    }
  }

  void _cancelHidingVolumeControls() {
    if (_hideVolumeControlsTimer != null && _hideVolumeControlsTimer.isActive) {
      _hideVolumeControlsTimer.cancel();
      _hideVolumeControlsTimer = null;
    }
  }

  void _scheduleHidingVolumeControls([int seconds = 4]) {
    _cancelHidingVolumeControls();
    _hideVolumeControlsTimer =
        Timer(Duration(seconds: seconds), () => _toggleVolumeControls(false));
  }

  void _onPopupMenuChoice(PopupMenuChoice choice) {
    switch (choice) {
      case PopupMenuChoice.AUDIO_TRACK:
        _chooseAudioTrack();
        break;
      case PopupMenuChoice.FULLSCREEN:
        _toggleFullScreen();
        break;
      case PopupMenuChoice.SUBTITLE_TRACK:
        _chooseSubtitleTrack();
        break;
      case PopupMenuChoice.RANDOM_PLAY:
        _toggleRandom();
        break;
      case PopupMenuChoice.REPEAT:
        _toggleRepeat();
        break;
      case PopupMenuChoice.LOOP:
        _toggleLoop();
        break;
      case PopupMenuChoice.EMPTY_PLAYLIST:
        _emptyPlaylist();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                color: _headerFooterBgColor,
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.only(left: 14),
                    dense: widget.settings.dense,
                    title: Text(
                      playing == null && title.isEmpty
                          ? 'VLC Remote' +
                              (lastStatusResponse != null
                                  ? ' (${lastStatusResponse.version})'
                                  : '')
                          : playing?.title ??
                              cleanVideoTitle(
                                  title.split(RegExp(r'[\\/]')).last),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Visibility(
                          visible: ticker != null ? !ticker.isActive : true,
                          child: IconButton(
                            icon: Icon(Icons.refresh),
                            onPressed: _updateStateAndPlaylist,
                            tooltip: 'Refresh VLC status',
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.settings),
                          tooltip: 'Show settings',
                          onPressed: () {
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
                          },
                        ),
                        Visibility(
                          visible: lastStatusResponseCode == 200,
                          child: PopupMenuButton<PopupMenuChoice>(
                            onSelected: _onPopupMenuChoice,
                            itemBuilder: (context) {
                              return [
                                PopupMenuItem(
                                  child: Text('Select subtitle track'),
                                  value: PopupMenuChoice.SUBTITLE_TRACK,
                                  enabled:
                                      (lastStatusResponse?.subtitleTracks ?? [])
                                          .isNotEmpty,
                                ),
                                PopupMenuItem(
                                  child: Text('Select audio track'),
                                  value: PopupMenuChoice.AUDIO_TRACK,
                                  enabled:
                                      (lastStatusResponse?.audioTracks ?? [])
                                          .isNotEmpty,
                                ),
                                PopupMenuItem(
                                  child: Text('Turn fullscreen '
                                      '${lastStatusResponse.fullscreen ? 'OFF' : 'ON'}'),
                                  value: PopupMenuChoice.FULLSCREEN,
                                  enabled: lastStatusResponse != null,
                                ),
                                PopupMenuItem(
                                  child: Text('Turn random play '
                                      '${lastStatusResponse.random ? 'OFF' : 'ON'}'),
                                  value: PopupMenuChoice.RANDOM_PLAY,
                                  enabled: lastStatusResponse != null,
                                ),
                                PopupMenuItem(
                                  child: Text('Turn repeat '
                                      '${lastStatusResponse.repeat ? 'OFF' : 'ON'}'),
                                  value: PopupMenuChoice.REPEAT,
                                  enabled: lastStatusResponse != null,
                                ),
                                PopupMenuItem(
                                  child: Text('Turn looping '
                                      '${lastStatusResponse.loop ? 'OFF' : 'ON'}'),
                                  value: PopupMenuChoice.LOOP,
                                  enabled: lastStatusResponse != null,
                                ),
                                PopupMenuItem(
                                  child: Text('Clear playlist'),
                                  value: PopupMenuChoice.EMPTY_PLAYLIST,
                                  enabled: lastStatusResponse != null,
                                ),
                              ];
                            },
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
              Divider(height: 0),
              _body(),
              !_showVolumeControls && !_animatingVolumeControls
                  ? Divider(height: 0)
                  : SizedBox(height: 0),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (playlist == null || playlist.isEmpty) {
      return Expanded(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: lastPlaylistResponseCode == 200
              ? Image.asset('assets/icon-512.png')
              : ConnectionAnimation(),
        ),
      );
    }

    var theme = Theme.of(context);

    return Expanded(
      child: Stack(
        children: [
          ListView.builder(
            itemCount: playlist.length,
            itemBuilder: (context, index) {
              var item = playlist[index];
              var icon = item.icon;
              if (item.current) {
                switch (state) {
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
                trailing: item.isMedia ? Text(formatTime(item.duration)) : null,
                onTap: () {
                  if (item.current) {
                    _pause();
                  } else {
                    _play(item);
                  }
                },
                onLongPress: () {
                  _delete(item);
                },
              );
            },
          ),
          Positioned.fill(
            child: Column(
              children: <Widget>[
                Spacer(),
                TweenAnimationBuilder(
                  tween: Tween<Offset>(
                      begin: Offset(0, 1),
                      end: Offset(0, _showVolumeControls ? 0 : 1)),
                  duration: Duration(milliseconds: 250),
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

  Widget _buildVolumeControls() {
    return Column(
      children: <Widget>[
        Divider(height: 0),
        Container(
          color: _headerFooterBgColor,
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: Colors.transparent,
            child: Row(
              children: <Widget>[
                // Volume down
                IconButton(
                  icon: Icon(Icons.remove),
                  tooltip: 'Decrease volume',
                  onPressed: _volume > 0
                      ? () {
                          if (!_showVolumeControls) {
                            _showVolumeControls = true;
                          }
                          _volumeRelative(-25);
                          _scheduleHidingVolumeControls(2);
                        }
                      : null,
                ),
                // Volume slider
                Expanded(
                  flex: 1,
                  child: Slider(
                    label: '${_volumeSliderValue().round()}%',
                    divisions: 200,
                    max: 200,
                    value: _volumeSliderValue(),
                    onChangeStart: (percent) {
                      setState(() {
                        _volumeSliding = true;
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
                      Throttle.milliseconds(_volumeSlidingThrottleMilliseconds,
                          _volumePercent, [percent], {#finished: false});
                    },
                    onChangeEnd: (percent) {
                      _volumePercent(percent);
                      if (percent == 0.0) {
                        _preMuteVolume = null;
                      }
                      setState(() {
                        _volumeSliding = false;
                      });
                      _scheduleHidingVolumeControls(2);
                    },
                  ),
                ),
                // Volume up
                IconButton(
                  icon: Icon(Icons.add),
                  tooltip: 'Increase volume',
                  onPressed: _volume < 512
                      ? () {
                          if (!_showVolumeControls) {
                            _showVolumeControls = true;
                          }
                          _volumeRelative(25);
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

  Widget _footer() {
    var theme = Theme.of(context);
    return Visibility(
      visible:
          widget.settings.connection.isValid && lastStatusResponseCode == 200,
      child: Container(
        color: _headerFooterBgColor,
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () {
                        _togglePolling(context);
                      },
                      child: Text(
                        state != 'stopped' ? formatTime(time) : '––:––',
                        style: TextStyle(
                          color: ticker.isActive
                              ? theme.textTheme.bodyText2.color
                              : theme.disabledColor,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      divisions: 100,
                      max: state != 'stopped' ? 100 : 0,
                      value: _sliderValue(),
                      onChangeStart: (percent) {
                        setState(() {
                          sliding = true;
                        });
                      },
                      onChanged: (percent) {
                        setState(() {
                          time = Duration(
                            seconds: (length.inSeconds / 100 * percent).round(),
                          );
                        });
                      },
                      onChangeEnd: (percent) async {
                        await _seekPercent(percent.round());
                        setState(() {
                          sliding = false;
                        });
                      },
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        showTimeLeft = !showTimeLeft;
                      });
                    },
                    child: Text(
                      state != 'stopped' && length != Duration.zero
                          ? showTimeLeft
                              ? '-' + formatTime(length - time)
                              : formatTime(length)
                          : '––:––',
                    ),
                  ),
                  SizedBox(width: 12),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: _toggleVolumeControls,
                      onLongPress: () {
                        if (_volume > 0) {
                          _preMuteVolume = _volume;
                          _volumePercent(0);
                        } else {
                          _volumePercent(_preMuteVolume != null
                              ? _preMuteVolume / volumeSliderScaleFactor
                              : 100);
                        }
                      },
                      child: Icon(_volume == 0
                          ? Icons.volume_off
                          : _volume < 102
                              ? Icons.volume_mute
                              : _volume < 218
                                  ? Icons.volume_down
                                  : Icons.volume_up),
                    ),
                  )
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 9, right: 9, bottom: 6, top: 3),
              child: Row(
                // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  GestureDetector(
                    child: Icon(
                      Icons.stop,
                      size: 30,
                    ),
                    onTap: _stop,
                  ),
                  Expanded(child: VerticalDivider()),
                  GestureDetector(
                    child: Icon(
                      Icons.skip_previous,
                      size: 30,
                    ),
                    onTap: _previous,
                  ),
                  Expanded(child: VerticalDivider()),
                  GestureDetector(
                    child: Icon(
                      Icons.fast_rewind,
                      size: 30,
                    ),
                    onTap: () {
                      _seekRelative(-5);
                    },
                  ),
                  Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: GestureDetector(
                        onTap: _pause,
                        child: Icon(
                          state == 'paused' || state == 'stopped'
                              ? Icons.play_arrow
                              : Icons.pause,
                          size: 42,
                        ),
                      )),
                  GestureDetector(
                    child: Icon(
                      Icons.fast_forward,
                      size: 30,
                    ),
                    onTap: () {
                      _seekRelative(5);
                    },
                  ),
                  Expanded(child: VerticalDivider()),
                  GestureDetector(
                    child: Icon(
                      Icons.skip_next,
                      size: 30,
                    ),
                    onTap: _next,
                  ),
                  Expanded(child: VerticalDivider()),
                  GestureDetector(
                    child: Icon(
                      Icons.eject,
                      size: 30,
                    ),
                    onTap: _openMedia,
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
  @override
  State<StatefulWidget> createState() => _ConnectionAnimationState();
}

class _ConnectionAnimationState extends State<ConnectionAnimation>
    with TickerProviderStateMixin {
  AnimationController _controller;
  Animation<int> _animation;

  @override
  void initState() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _animation = IntTween(begin: 0, end: 3).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    super.initState();
  }

  @override
  dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: AlignmentDirectional.center,
      children: <Widget>[
        Image.asset('assets/cone.png'),
        AnimatedBuilder(
          animation: _animation,
          builder: (BuildContext context, Widget child) {
            return Image.asset(
              'assets/signal-${_animation.value}.png',
            );
          },
        ),
        Positioned(
          bottom: 0,
          child: Text('Trying to connect to VLC...'),
        )
      ],
    );
  }
}
