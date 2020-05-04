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
  String _errorMessage;
  String _errorDetail;
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

    http.Response response;

    try {
      response = await http.get(
        Uri.http(widget.settings.connection.authority, '/requests/browse.xml', {
          'uri': dir.uri,
        }),
        headers: {
          'Authorization': 'Basic ' +
              base64Encode(
                  utf8.encode(':${widget.settings.connection.password}')),
        },
      ).timeout(Duration(seconds: 2));
    } catch (e) {
      setState(() {
        _errorMessage = 'Error connecting to VLC';
        _errorDetail = e.runtimeType.toString();
        _loading = false;
      });
      return;
    }

    List<BrowseItem> dirs = [];
    List<BrowseItem> files = [];

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

        if (item.isDir) {
          dirs.add(item);
        } else if (item.isSupportedMedia) {
          files.add(item);
        }
      });
    }

    dirs.sort((a, b) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    files.sort((a, b) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    setState(() {
      _items = dirs + files;
      _loading = false;
    });
  }

  _handleTap(BrowseItem item) async {
    if (item.isDir) {
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
      Navigator.pop(context, BrowseResult(item));
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

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ListTile(
              leading: Icon(
                Icons.error,
                color: Colors.redAccent,
                size: 48,
              ),
              title: Text(_errorMessage),
              subtitle: Text(_errorDetail),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[Text('No compatible files found')],
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
        if (_items[i].isDir && i < _items.length - 1 && _items[i + 1].isFile) {
          return Divider();
        }
        return SizedBox.shrink();
      },
    );
  }
}
