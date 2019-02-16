import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

import 'models.dart';

class FileBrowser extends StatefulWidget {
  final BrowseItem dir;
  final bool Function(BrowseItem) isFave;
  final Function(BrowseItem) onToggleFave;
  final Settings settings;

  FileBrowser({
    @required this.dir,
    @required this.isFave,
    @required this.onToggleFave,
    @required this.settings,
  });

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

  _getListing(BrowseItem dir) async {
    setState(() {
      _loading = true;
    });

    var response = await http.get(
      Uri.http('$vlcHost:$vlcPort', '/requests/browse.xml', {'uri': dir.uri}),
      headers: {
        'Authorization': 'Basic ' + base64Encode(utf8.encode(':$vlcPassword')),
      },
    );

    List<BrowseItem> items = [];
    var dirIndex = 0;

    if (response.statusCode == 200) {
      var document = xml.parse(response.body);
      document.findAllElements('element').forEach((el) {
        var item = BrowseItem(
          el.getAttribute('type'),
          el.getAttribute('name'),
          el.getAttribute('path'),
          el.getAttribute('uri'),
        );

        if (item.name == '..') {
          return;
        }

        if (item.type == 'dir') {
          items.insert(dirIndex++, item);
        } else if (item.isMovie) {
          items.add(item);
        }
      });
    }

    setState(() {
      _items = items;
      _loading = false;
    });
  }

  _handleTap(BrowseItem item) async {
    if (item.type == 'dir') {
      BrowseResult result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FileBrowser(
                dir: item,
                isFave: widget.isFave,
                onToggleFave: widget.onToggleFave,
                settings: widget.settings,
              ),
        ),
      );
      if (result != null) {
        Navigator.pop(context, result);
      }
    } else {
      Navigator.pop(
        context,
        BrowseResult(
          item,
          _items.where((i) => i.type == 'file').toList(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.dir.title),
        actions: widget.dir.path != ''
            ? <Widget>[
                IconButton(
                  onPressed: () {
                    setState(() {
                      widget.onToggleFave(widget.dir);
                    });
                  },
                  icon: Icon(
                    widget.isFave(widget.dir) ? Icons.star : Icons.star_border,
                    color: Colors.white,
                  ),
                )
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
          children: <Widget>[CircularProgressIndicator()],
        ),
      );
    }

    return ListView.separated(
      itemCount: _items.length,
      itemBuilder: (context, i) {
        var item = _items[i];
        return ListTile(
          dense: widget.settings.dense,
          leading: Icon(item.icon),
          title: Text(item.title),
          enabled: !_loading,
          onTap: () {
            _handleTap(item);
          },
        );
      },
      separatorBuilder: (context, i) {
        if (_items[i].type == 'dir' && _items[i + 1]?.type == 'file') {
          return Divider();
        }
        return SizedBox.shrink();
      },
    );
  }
}
