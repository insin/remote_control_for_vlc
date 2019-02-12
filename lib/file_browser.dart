import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

import 'models.dart';

class FileBrowser extends StatefulWidget {
  final BrowseItem dir;
  final bool Function(BrowseItem) isFave;
  final Function(BrowseItem) onToggleFave;

  FileBrowser(
      {@required this.dir, @required this.isFave, @required this.onToggleFave});

  @override
  State<StatefulWidget> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  bool _loading = false;
  List<BrowseItem> _items = [];

  @override
  void initState() {
    _getListing(widget.dir);
    super.initState();
  }

  _getListing(BrowseItem dir) {
    setState(() {
      _loading = true;
    });

    http.get(
        Uri.http('10.0.2.2:8080', '/requests/browse.xml', {'uri': dir.uri}),
        headers: {
          'Authorization': 'Basic ' + base64Encode(utf8.encode(':vlcplayer'))
        }).then((http.Response response) {
      List<BrowseItem> items = [];
      var dirIndex = 0;
      if (response.statusCode == 200) {
        var document = xml.parse(response.body);
        document.findAllElements('element').forEach((el) {
          var item = BrowseItem(
              el.getAttribute('type'),
              el.getAttribute('name'),
              el.getAttribute('path'),
              el.getAttribute('uri'));
          if (item.name == '..') {
            return;
          }
          if (item.type == 'dir') {
            items.insert(dirIndex++, item);
          } else {
            items.add(item);
          }
        });
      }

      setState(() {
        _items = items;
        _loading = false;
      });
    });
  }

  _handleTap(BrowseItem item) async {
    if (item.type == 'dir') {
      BrowseItem selectedFile = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => FileBrowser(
                  dir: item,
                  isFave: widget.isFave,
                  onToggleFave: widget.onToggleFave,
                )),
      );
      if (selectedFile != null) {
        Navigator.pop(context, selectedFile);
      }
    } else {
      Navigator.pop(context, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.dir.name),
        actions: widget.dir.path != ''
            ? <Widget>[
                IconButton(
                    onPressed: () {
                      setState(() {
                        widget.onToggleFave(widget.dir);
                      });
                    },
                    icon: Icon(
                      widget.isFave(widget.dir)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: Colors.white,
                    ))
              ]
            : null,
      ),
      body: _renderList(),
    );
  }

  _renderList() {
    if (_loading) {
      return Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [CircularProgressIndicator()],
      ));
    }

    return ListView(
        children: _items
            .map((item) => ListTile(
                  leading: item.type == 'dir'
                      ? Icon(Icons.folder)
                      : Icon(Icons.insert_drive_file),
                  title: Text(item.name),
                  enabled: !_loading,
                  onTap: () {
                    _handleTap(item);
                  },
                ))
            .toList());
  }
}
