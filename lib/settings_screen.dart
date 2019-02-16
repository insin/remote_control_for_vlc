import 'package:flutter/material.dart';

import 'models.dart';

class SettingsScreen extends StatefulWidget {
  final Settings settings;
  final Function onSettingsChanged;

  SettingsScreen({@required this.settings, @required this.onSettingsChanged});

  @override
  State<StatefulWidget> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: ListView(
        children: <Widget>[
          ListTile(
            dense: widget.settings.dense,
            title: Text(
              'Connection details',
              style: Theme.of(context).textTheme.subhead,
            ),
          ),
          ListTile(
            dense: widget.settings.dense,
            title: TextField(
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Computer IP'),
            ),
          ),
          ListTile(
            dense: widget.settings.dense,
            title: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'VLC Server Port (default: 8080)',
              ),
            ),
          ),
          ListTile(
            dense: widget.settings.dense,
            title: TextField(
              obscureText: true,
              decoration: InputDecoration(labelText: 'VLC Password'),
            ),
          ),
          Divider(),
          ListTile(
            dense: widget.settings.dense,
            title: Text(
              'Display options',
              style: Theme.of(context).textTheme.subhead,
            ),
          ),
          SwitchListTile(
            title: Text('Compact display'),
            value: widget.settings.dense,
            dense: widget.settings.dense,
            onChanged: (dense) {
              setState(() {
                widget.settings.dense = dense;
                widget.onSettingsChanged();
              });
            },
          ),
        ],
      ),
    );
  }
}
