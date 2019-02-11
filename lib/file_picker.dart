import 'package:flutter/material.dart';

import 'browser.dart';
import 'models.dart';

var fileSystemItem = BrowseItem('dir', 'File System', '', 'file:///');
var homeFolderItem = BrowseItem('dir', 'Home', '', 'file://~');

class FilePicker extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _FilePickerState();
}

class _FilePickerState extends State<FilePicker> {
  List<BrowseItem> _faves = [];

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
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> listItems = [
      ListTile(
          title: Text('File System'),
          leading: Icon(Icons.folder),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => Browser(
                        dir: fileSystemItem,
                        isFave: _isFave,
                        onToggleFave: _toggleFave,
                      )),
            );
          }),
      ListTile(
          title: Text('Home Folder'),
          leading: Icon(Icons.home),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => Browser(
                        dir: homeFolderItem,
                        isFave: _isFave,
                        onToggleFave: _toggleFave,
                      )),
            );
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => Browser(
                            dir: item,
                            isFave: _isFave,
                            onToggleFave: _toggleFave)),
                  );
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
