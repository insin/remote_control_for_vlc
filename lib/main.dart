import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_control.dart';

void main() async {
  var prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;

  MyApp({@required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VLC Remote',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
      ),
      home: RemoteControl(prefs: prefs),
    );
  }
}
