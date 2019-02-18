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
  String state = 'stopped';
  String title = '';
  Duration time = Duration.zero;
  Duration length = Duration.zero;

  Timer ticker;
  bool showTimeLeft = false;
  bool sliding = false;

  BrowseItem playing;
  List<BrowseItem> playlist;

  Future<xml.XmlDocument> _statusRequest(
      [Map<String, String> queryParameters]) async {
    var response = await http.get(
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
    );
    if (response.statusCode == 200) {
      return xml.parse(response.body);
    }
    return null;
  }

  @override
  initState() {
    ticker = new Timer.periodic(Duration(seconds: 1), _tick);
    super.initState();
    _checkWifi();
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
    if (!widget.settings.connection.isValid) {
      return;
    }

    var document = await _statusRequest();
    // TODO Try to detect if the playing file was changed from VLC itself and switch back to default display
    setState(() {
      state = document.findAllElements('state').first.text;
      if (!sliding) {
        time = Duration(
          seconds: int.tryParse(document.findAllElements('time').first.text),
        );
      }
      length = Duration(
          seconds: int.tryParse(document.findAllElements('length').first.text));
      Map<String, String> titles = Map.fromIterable(
        document.findAllElements('info').where(
            (el) => ['title', 'filename'].contains(el.getAttribute('name'))),
        key: (el) => el.getAttribute('name'),
        value: (el) => el.text,
      );
      title = titles['title'] ?? titles['filename'] ?? '';
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
      _statusRequest({
        'command': 'in_play',
        'input': result.item.uri,
      });
      setState(() {
        playing = result.item;
        playlist = result.playlist;
      });
    }
  }

  _play(BrowseItem item) {
    _statusRequest({
      'command': 'in_play',
      'input': item.uri,
    });
    setState(() {
      playing = item;
    });
  }

  _seekPercent(int percent) async {
    var document = await _statusRequest({
      'command': 'seek',
      'val': '$percent%',
    });
    setState(() {
      time = Duration(
          seconds: int.tryParse(document.findAllElements('time').first.text));
    });
  }

  _seekRelative(int seekTime) async {
    var document = await _statusRequest({
      'command': 'seek',
      'val': '''${seekTime > 0 ? '+' : ''}${seekTime}S''',
    });
    setState(() {
      time = Duration(
          seconds: int.tryParse(document.findAllElements('time').first.text));
    });
  }

  _pause() {
    _statusRequest({
      'command': 'pl_pause',
    });
    // Pre-empt the expected state so the button feels more responsive
    setState(() {
      state = (state == 'playing' ? 'paused' : 'playing');
    });
  }

  _stop() {
    _statusRequest({
      'command': 'pl_stop',
    });
    // Pre-empt the expected state so the button feels more responsive
    setState(() {
      state = 'stopped';
      time = Duration.zero;
      length = Duration.zero;
    });
  }

  double _sliderValue() {
    if (length.inSeconds == 0) {
      return 0.0;
    }
    return (time.inSeconds / length.inSeconds * 100);
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
                  trailing: IconButton(
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
          child: Image.asset('assets/icon-512.png'),
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
            leading: Icon(playing.icon),
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
                Text(
                  state != 'stopped' ? formatTime(time) : '––:––',
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
