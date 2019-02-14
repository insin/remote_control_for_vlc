import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart' as xml;

import 'models.dart';
import 'open_media.dart';

String _formatTime(Duration duration) {
  String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '${duration.inHours >= 1 ? duration.inHours.toString() + ':' : ''}$minutes:$seconds';
}

class RemoteControl extends StatefulWidget {
  final SharedPreferences prefs;

  RemoteControl({@required this.prefs});

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

  Future<xml.XmlDocument> _statusRequest(
      [Map<String, String> queryParameters]) async {
    var response = await http.get(
        Uri.http('10.0.2.2:8080', '/requests/status.xml', queryParameters),
        headers: {
          'Authorization': 'Basic ' + base64Encode(utf8.encode(':vlcplayer'))
        });
    if (response.statusCode == 200) {
      return xml.parse(response.body);
    }
    return null;
  }

  @override
  initState() {
    ticker = new Timer.periodic(Duration(seconds: 1), _tick);
    super.initState();
  }

  _tick(timer) async {
    var document = await _statusRequest();
    setState(() {
      state = document.findAllElements('state').first.text;
      if (!sliding) {
        time = Duration(
            seconds: int.tryParse(document.findAllElements('time').first.text));
      }
      length = Duration(
          seconds: int.tryParse(document.findAllElements('length').first.text));
      Map<String, String> titles = Map.fromIterable(
          document.findAllElements('info').where(
              (el) => ['title', 'filename'].contains(el.getAttribute('name'))),
          key: (el) => el.getAttribute('name'),
          value: (el) => el.text);
      title = titles['title'] ?? titles['filename'] ?? '';
    });
  }

  _openMedia() async {
    BrowseItem item = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => OpenMedia(prefs: widget.prefs)),
    );

    if (item != null) {
      _statusRequest({
        'command': 'in_play',
        'input': item.uri,
      });
    }
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
        padding: EdgeInsets.symmetric(
          vertical: 12.0,
          horizontal: 12.0,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(children: [
              Flexible(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.title,
                    textAlign: TextAlign.center,
                  )
                ],
              )),
            ]),
            Expanded(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Image.asset('assets/vlc-icon.png')),
            ),
            Container(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      state != 'stopped' ? _formatTime(time) : '––:––',
                      style: TextStyle(fontSize: 12),
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
                                  seconds: (length.inSeconds / 100 * percent)
                                      .round());
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
                                ? '-' + _formatTime(length - time)
                                : _formatTime(length)
                            : '––:––',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                )),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                CircleButton(
                  Icons.fast_rewind,
                  onPressed: () {
                    _seekRelative(-10);
                  },
                ),
                CircleButton(
                  state == 'paused' || state == 'stopped'
                      ? Icons.play_arrow
                      : Icons.pause,
                  onPressed: _pause,
                ),
                CircleButton(
                  Icons.stop,
                  onPressed: _stop,
                ),
                CircleButton(
                  Icons.fast_forward,
                  onPressed: () {
                    _seekRelative(10);
                  },
                ),
                CircleButton(
                  Icons.eject,
                  onPressed: _openMedia,
                ),
              ],
            )
          ],
        ),
      ),
    ));
  }
}

class CircleButton extends StatelessWidget {
  final IconData icon;
  final Function onPressed;

  CircleButton(this.icon, {@required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return RawMaterialButton(
      constraints: BoxConstraints(minWidth: 20, minHeight: 40),
      onPressed: onPressed,
      child: new Icon(
        icon,
        color: Theme.of(context).primaryTextTheme.button.color,
        size: 26.0,
      ),
      shape: new CircleBorder(),
      elevation: 1.0,
      fillColor: Theme.of(context).primaryColor,
      padding: EdgeInsets.all(12),
    );
  }
}
