import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'remote_control.dart';

void main() async {
  var prefs = await SharedPreferences.getInstance();
  runApp(VlcRemote(prefs: prefs, settings: Settings(prefs)));
}

class VlcRemote extends StatelessWidget {
  final SharedPreferences prefs;
  final Settings settings;

  VlcRemote({
    @required this.prefs,
    @required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VLC Remote',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
      ),
      home: RemoteControl(prefs: prefs, settings: settings),
    );
  }
}
