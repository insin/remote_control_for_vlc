import 'package:flutter/material.dart';

import 'file_picker.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VLC Remote',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      home: FilePicker(),
    );
  }
}
