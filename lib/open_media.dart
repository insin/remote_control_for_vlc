import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_browser.dart';
import 'models.dart';

var fileSystemItem = BrowseItem('dir', 'File System', '', 'file:///');
var homeFolderItem = BrowseItem('dir', 'Home', '', 'file://~');

class OpenMedia extends StatefulWidget {
  final SharedPreferences prefs;

  OpenMedia({@required this.prefs});

  @override
  State<StatefulWidget> createState() => _OpenMediaState();
}

class _OpenMediaState extends State<OpenMedia> {
  List<BrowseItem> _faves;

  @override
  initState() {
    _faves = (jsonDecode(widget.prefs.getString('faves') ?? '[]') as List)
        .map((obj) => BrowseItem.fromJson(obj))
        .toList();
    super.initState();
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
    BrowseItem selectedFile = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => FileBrowser(
                dir: dir,
                isFave: _isFave,
                onToggleFave: _toggleFave,
              )),
    );
    if (selectedFile != null) {
      Navigator.pop(context, selectedFile);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> listItems = <Widget>[
      ListTile(
          title: Text('File System'),
          leading: Icon(Icons.folder),
          onTap: () {
            _selectFile(fileSystemItem);
          }),
      ListTile(
          title: Text('Home Folder'),
          leading: Icon(Icons.home),
          onTap: () {
            _selectFile(homeFolderItem);
          }),
    ];

    if (_faves.isNotEmpty) {
      listItems.addAll([
        Divider(),
        ListTile(
          title: Text('Faves', style: Theme.of(context).textTheme.subtitle),
        ),
      ]);
      listItems.addAll(_faves.map((item) => Dismissible(
            key: Key(item.path),
            background: LeaveBehindView(),
            child: ListTile(
                title: Text(item.name),
                leading: Icon(Icons.folder_special),
                onTap: () {
                  _selectFile(item);
                }),
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
    return new Container(
      color: Colors.red,
      padding: const EdgeInsets.all(16.0),
      child: new Row(
        children: [
          new Icon(Icons.delete, color: Colors.white),
          new Expanded(
            child: new Text(''),
          ),
          new Icon(Icons.delete, color: Colors.white),
        ],
      ),
    );
  }
}
