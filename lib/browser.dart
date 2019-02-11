import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

import 'models.dart';

class Browser extends StatefulWidget {
  final BrowseItem dir;
  final bool Function(BrowseItem) isFave;
  final Function(BrowseItem) onToggleFave;

  Browser(
      {@required this.dir, @required this.isFave, @required this.onToggleFave});

  @override
  State<StatefulWidget> createState() => _BrowserState();
}

class _BrowserState extends State<Browser> {
  bool _loading = false;
  String _host = '10.0.2.2:8080';
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

    http.get(Uri.http(_host, '/requests/browse.xml', {'uri': dir.uri}),
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

  _handleTap(BrowseItem item) {
    if (item.type == 'dir') {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => Browser(
                  dir: item,
                  isFave: widget.isFave,
                  onToggleFave: widget.onToggleFave,
                )),
      );
    } else {
      print('Selected ${item.path}');
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
                  leading: item.type == 'dir' ? Icon(Icons.folder) : null,
                  title: Text(item.name),
                  enabled: !_loading,
                  onTap: () {
                    _handleTap(item);
                  },
                ))
            .toList());
  }
}
