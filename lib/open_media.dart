import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_browser.dart';
import 'models.dart';
import 'utils.dart';
import 'widgets.dart';

var fileSystemItem = BrowseItem('dir', 'File System', '', 'file:///');

/// Allow some commonly-used media URLs without protocols to pass for Copied URL
var probablyMediaUrlRegExp = RegExp([
  r'(www\.)?dailymotion\.com/video/',
  r'(www\.)?soundcloud\.com/.+/.+',
  r'((www|gaming)\.)?youtube\.com/|youtu\.be/',
  r'(www\.)?vimeo\.com/(channels/.+/)?\d+|player\.vimeo\.com/',
].join('|'));

class OpenMedia extends StatefulWidget {
  final SharedPreferences prefs;
  final Settings settings;

  OpenMedia({
    @required this.prefs,
    @required this.settings,
  });

  @override
  State<StatefulWidget> createState() => _OpenMediaState();
}

class _OpenMediaState extends State<OpenMedia> with WidgetsBindingObserver {
  List<BrowseItem> _faves;
  BrowseItem _clipboardUrlItem;
  String _otherUrl;

  @override
  initState() {
    _faves = (jsonDecode(widget.prefs.getString('faves') ?? '[]') as List)
        .map((obj) => BrowseItem.fromJson(obj))
        .toList();
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkClipboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  _checkClipboard() async {
    BrowseItem urlItem;
    var data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null &&
        (data.text.startsWith(urlRegExp) ||
            data.text.startsWith(probablyMediaUrlRegExp))) {
      urlItem = BrowseItem.fromUrl(data.text);
    }
    setState(() {
      _clipboardUrlItem = urlItem;
    });
  }

  _handleOtherUrl(intent) {
    if (_otherUrl == null || _otherUrl.isEmpty) {
      return;
    }
    Navigator.pop(context, BrowseResult(BrowseItem.fromUrl(_otherUrl), intent));
  }

  bool _isFave(BrowseItem item) {
    return _faves.any((fave) => item.path == fave.path);
  }

  _toggleFave(BrowseItem item) {
    setState(() {
      var index = _faves.indexWhere((fave) => item.path == fave.path);
      if (index != -1) {
        _faves.removeAt(index);
      } else {
        _faves.add(item);
      }
      widget.prefs.setString('faves', jsonEncode(_faves));
    });
  }

  _selectFile(BrowseItem dir) async {
    BrowseResult result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileBrowser(
          dir: dir,
          isFave: _isFave,
          onToggleFave: _toggleFave,
          settings: widget.settings,
        ),
      ),
    );
    if (result != null) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> listItems = <Widget>[
      ListTile(
        dense: widget.settings.dense,
        title: Text('File System'),
        leading: Icon(Icons.folder),
        onTap: () {
          _selectFile(fileSystemItem);
        },
      ),
      if (_clipboardUrlItem != null)
        EnqueueMenuGestureDetector(
          item: _clipboardUrlItem,
          child: ListTile(
            dense: widget.settings.dense,
            title: Text('Copied URL'),
            subtitle: Text(_clipboardUrlItem.uri),
            leading: Icon(Icons.public),
            onTap: () {
              Navigator.pop(context,
                  BrowseResult(_clipboardUrlItem, BrowseResultIntent.play));
            },
          ),
        ),
      ExpansionTile(
        leading: Icon(Icons.public),
        title: Text('${_clipboardUrlItem != null ? 'Other ' : ''}URL'),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                TextFormField(
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onChanged: (url) {
                    setState(() {
                      _otherUrl = url;
                    });
                  },
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: RaisedButton(
                        child: Text('Play'),
                        onPressed: () =>
                            _handleOtherUrl(BrowseResultIntent.play),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: RaisedButton(
                        child: Text('Enqueue'),
                        onPressed: () =>
                            _handleOtherUrl(BrowseResultIntent.enqueue),
                      ),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    ];

    if (_faves.isNotEmpty) {
      listItems.addAll([
        Divider(),
        ListTile(
          dense: widget.settings.dense,
          title: Text('Starred', style: Theme.of(context).textTheme.subtitle2),
        ),
      ]);
      listItems.addAll(_faves.map((item) => Dismissible(
            key: Key(item.path),
            background: LeaveBehindView(),
            child: ListTile(
              dense: widget.settings.dense,
              title: Text(item.name),
              leading: Icon(Icons.folder_special),
              onTap: () {
                _selectFile(item);
              },
            ),
            onDismissed: (direction) {
              _toggleFave(item);
            },
          )));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Open Media'),
      ),
      body: ListView(children: listItems),
    );
  }
}

class LeaveBehindView extends StatelessWidget {
  LeaveBehindView({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.red,
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: <Widget>[
          Icon(Icons.delete, color: Colors.white),
          Expanded(
            child: Text(''),
          ),
          Icon(Icons.delete, color: Colors.white),
        ],
      ),
    );
  }
}
