import 'dart:async';
import 'dart:convert';

import 'package:connectivity/connectivity.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;

import 'models.dart';
import 'open_media.dart';
import 'settings_screen.dart';
import 'utils.dart';

var headerFooterBgColor = Colors.grey.shade200.withOpacity(0.75);

enum PopupMenuChoice { AUDIO_TRACK, FULLSCREEN, SUBTITLE_TRACK }

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
  int lastStatusCode;
  VlcStatusResponse lastStatusResponse;
  String state = 'stopped';
  String title = '';
  Duration time = Duration.zero;
  Duration length = Duration.zero;

  Timer ticker;
  bool showTimeLeft = false;
  bool sliding = false;
  bool skipNextStatus = false;

  BrowseItem playing;
  List<BrowseItem> playlist;

  @override
  initState() {
    ticker = new Timer.periodic(Duration(seconds: 1), _tick);
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
    http.Response response;
    try {
      assert(() {
        print('VlcStatusRequest(${queryParameters ?? {}})');
        return true;
      }());
      response = await client.get(
        Uri.http(
          widget.settings.connection.authority,
          '/requests/status.xml',
          queryParameters,
        ),
        headers: {
          'Authorization': 'Basic ' +
              base64Encode(
                  utf8.encode(':${widget.settings.connection.password}')),
        },
      ).timeout(Duration(seconds: 1));
    } catch (e) {
      assert(() {
        print('Error: ${e.runtimeType}');
        return true;
      }());
    }
    setState(() {
      lastStatusCode = response?.statusCode ?? -1;
    });
    if (response?.statusCode == 200) {
      var statusResponse = VlcStatusResponse(xml.parse(response.body));
      assert(() {
        print(statusResponse);
        return true;
      }());
      return statusResponse;
    }
    return null;
  }

  _togglePolling(context) {
    String message;
    if (ticker.isActive) {
      ticker.cancel();
      message = 'Paused polling for status updates';
    } else {
      ticker = new Timer.periodic(Duration(seconds: 1), _tick);
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
    if (widget.settings.connection.isNotValid) {
      return;
    }

    if (skipNextStatus) {
      skipNextStatus = false;
      return;
    }

    var response = await _statusRequest();

    if (response == null) {
      lastStatusResponse = response;
      return;
    }

    // TODO Try to detect if the playing file was changed from VLC itself and switch back to default display
    setState(() {
      state = response.state;
      length = response.length;
      title = response.title;
      if (!sliding) {
        time = response.time;
      }
      lastStatusResponse = response;
    });
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
      setState(() {
        playing = result.item;
        playlist = result.playlist;
      });
      assert(() {
        print('Playing ${result.item}');
        return true;
      }());
    }
  }

  _play(BrowseItem item) async {
    var response = await _statusRequest({
      'command': 'in_play',
      'input': item.uri,
    });
    if (response == null) {
      return;
    }
    setState(() {
      playing = item;
    });
  }

  _seekPercent(int percent) async {
    var response = await _statusRequest({
      'command': 'seek',
      'val': '$percent%',
    });
    if (response == null) {
      return;
    }
    setState(() {
      time = response.time;
    });
  }

  _seekRelative(int seekTime) async {
    var response = await _statusRequest({
      'command': 'seek',
      'val': '''${seekTime > 0 ? '+' : ''}${seekTime}S''',
    });
    if (response == null) {
      return;
    }
    setState(() {
      time = response.time;
    });
  }

  _pause() async {
    // Pre-empt the expected state so the button feels more responsive
    setState(() {
      state = (state == 'playing' ? 'paused' : 'playing');
      skipNextStatus = true;
    });
    _statusRequest({
      'command': 'pl_pause',
    });
  }

  _stop() {
    // Pre-empt the expected state so the button feels more responsive
    setState(() {
      state = 'stopped';
      time = Duration.zero;
      length = Duration.zero;
    });
    _statusRequest({
      'command': 'pl_stop',
    });
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
                    child: Text(option.language),
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
                color: headerFooterBgColor,
                child: ListTile(
                  contentPadding: EdgeInsets.only(left: 14),
                  dense: widget.settings.dense,
                  title: Text(
                    playing?.title ??
                        cleanTitle(title.split(new RegExp(r'[\\\/]')).last),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.settings),
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
                        visible: lastStatusCode == 200,
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
                                enabled: (lastStatusResponse?.audioTracks ?? [])
                                    .isNotEmpty,
                              ),
                              PopupMenuItem(
                                child: Text('Toggle fullscreen'),
                                value: PopupMenuChoice.FULLSCREEN,
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
              Divider(height: 0),
              _body(),
              Divider(height: 0),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (playlist == null) {
      return Expanded(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: lastStatusCode == 200
              ? Image.asset('assets/icon-512.png')
              : ConnectionAnimation(),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        itemCount: playlist.length,
        itemBuilder: (context, index) {
          var item = playlist[index];
          var isPlaying = item.path == playing.path;
          return ListTile(
            dense: widget.settings.dense,
            selected: isPlaying,
            leading: Icon(item.icon),
            title: Text(
              item.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onTap: () {
              _play(item);
            },
          );
        },
        // separatorBuilder: (context, index) => Divider(height: 0),
      ),
    );
  }

  Widget _footer() {
    return Container(
      color: headerFooterBgColor,
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
                                ? Theme.of(context).textTheme.body1.color
                                : Theme.of(context).disabledColor,
                          ),
                        ),
                      ),
                ),
                Flexible(
                    flex: 1,
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
                    )),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      showTimeLeft = !showTimeLeft;
                    });
                  },
                  child: Text(
                    state != 'stopped'
                        ? showTimeLeft
                            ? '-' + formatTime(length - time)
                            : formatTime(length)
                        : '––:––',
                  ),
                ),
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
                    Icons.fast_rewind,
                    size: 30,
                  ),
                  onTap: () {
                    _seekRelative(-10);
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
                    _seekRelative(10);
                  },
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
    _animation = new IntTween(begin: 0, end: 3).animate(CurvedAnimation(
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
