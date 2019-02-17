import 'dart:async';
import 'dart:convert';

import 'package:connectivity/connectivity.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class SettingsScreen extends StatefulWidget {
  final Settings settings;
  final Function onSettingsChanged;

  SettingsScreen({@required this.settings, @required this.onSettingsChanged});

  @override
  State<StatefulWidget> createState() => _SettingsScreenState();
}

var _ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
var _numericPattern = RegExp(r'^\d+$');

class Connection {
  String _ip;
  String _port;
  String _password;

  String _ipError;
  String _portError;
  String _passwordError;

  bool get isValid =>
      _ipError == null && _portError == null && _passwordError == null;

  get ip => _ip;
  get port => _port;
  get password => _password;
  get ipError => _ipError;
  get portError => _portError;
  get passwordError => _passwordError;

  set ip(String value) {
    if (value.trim().isEmpty) {
      _ipError = 'An IP address is required';
    } else if (!_ipPattern.hasMatch(value)) {
      _ipError = 'Must have 4 parts separated by periods';
    } else {
      _ipError = null;
    }
    _ip = value;
  }

  set port(String value) {
    _port = value;
    if (value.trim().isEmpty) {
      _portError = 'A port number is required';
    } else if (!_numericPattern.hasMatch(value)) {
      _portError = 'Must be all digits';
    } else {
      _portError = null;
    }
    _port = value;
  }

  set password(String value) {
    if (value.trim().isEmpty) {
      _passwordError = 'A password is required';
    } else {
      _passwordError = null;
    }
    _password = value;
  }
}

class _SettingsScreenState extends State<SettingsScreen> {
  Connection connection;
  var ipController = TextEditingController();
  var ipFocus = FocusNode();
  bool ipDirty = false;
  var portController = TextEditingController();
  var portFocus = FocusNode();
  bool portDirty = false;
  var passwordController = TextEditingController();
  var passwordFocus = FocusNode();
  bool passwordDirty = false;

  String prefilledIpSuffix;
  bool showPassword = false;

  bool testingConnection = false;
  String connectionTestResult;
  String connectionTestResultDescription;
  IconData connectionTestResultIcon;

  @override
  initState() {
    connection = Connection();

    ipController.addListener(() {
      setState(() {
        connection.ip = ipController.text;
      });
    });
    portController.addListener(() {
      setState(() {
        connection.port = portController.text;
      });
    });
    passwordController.addListener(() {
      setState(() {
        connection.password = passwordController.text;
      });
    });

    ipController.text = widget.settings.ip;
    portController.text = widget.settings.port;
    passwordController.text = widget.settings.password;

    ipFocus.addListener(() {
      if (!ipFocus.hasFocus) {
        setState(() {
          ipDirty = true;
        });
      }
    });
    portFocus.addListener(() {
      if (!portFocus.hasFocus) {
        setState(() {
          portDirty = true;
        });
      }
    });
    passwordFocus.addListener(() {
      if (!passwordFocus.hasFocus) {
        setState(() {
          passwordDirty = true;
        });
      }
    });

    super.initState();

    if (widget.settings.ip == '') {
      _defaultIpPrefix();
    }
  }

  @override
  dispose() {
    ipController.dispose();
    ipFocus.dispose();
    portController.dispose();
    portFocus.dispose();
    passwordController.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  _defaultIpPrefix() async {
    if (await Connectivity().checkConnectivity() == ConnectivityResult.wifi) {
      var ip = await Connectivity().getWifiIP();
      setState(() {
        prefilledIpSuffix =
            ip.substring(0, ip.lastIndexOf(new RegExp(r'\.')) + 1);
        ipController.text = prefilledIpSuffix;
      });
    }
  }

  _testConnection() async {
    if (!connection.isValid) {
      setState(() {
        ipDirty = true;
        portDirty = true;
        passwordDirty = true;
      });
      return;
    }

    setState(() {
      connectionTestResult = null;
      connectionTestResultIcon = null;
      connectionTestResultDescription = null;
      testingConnection = true;
    });

    String result;
    String description;
    IconData icon;

    var client = http.Client();

    try {
      var response = await client.get(
          Uri.http(
            '${ipController.text}:${portController.text}',
            '/requests/status.xml',
          ),
          headers: {
            'Authorization': 'Basic ' +
                base64Encode(utf8.encode(':${passwordController.text}'))
          }).timeout(Duration(seconds: 5));

      if (response.statusCode == 401) {
        result = 'Password is invalid';
        icon = Icons.warning;
      } else if (response.statusCode == 200) {
        result = 'Connection successful';
        icon = Icons.check;
      } else {
        result = 'Unexpected response code: ${response.statusCode}';
        icon = Icons.error;
      }
    } catch (e) {
      if (e is TimeoutException) {
        result = 'Connection timed out';
        description = 'Check the IP and port settings';
        icon = Icons.warning;
      } else {
        result = 'Unknown error: ${e.runtimeType}';
        icon = Icons.error;
      }
    }

    setState(() {
      connectionTestResult = result;
      connectionTestResultDescription = description;
      connectionTestResultIcon = icon;
      testingConnection = false;
    });
  }

  String _validateIp() {
    if (ipController.text.trim().isEmpty) {
      return 'An IP address is required';
    }
    if (!RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
        .hasMatch(ipController.text)) {
      return 'Must have 4 parts separated by periods';
    }
    return null;
  }

  String _validatePort() {
    if (portController.text.trim().isEmpty) {
      return 'A port number is required';
    }
    if (!RegExp(r'^\d+$').hasMatch(portController.text)) {
      return 'Must be all digits';
    }
    return null;
  }

  String _validatePassword() {
    if (passwordController.text.trim().isEmpty) {
      return 'A password is required';
    }
    return null;
  }

  bool _allValid() {
    return [_validateIp(), _validatePassword(), _validatePort()]
        .every((error) => error == null);
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: ListView(children: <Widget>[
        ListTile(
          dense: widget.settings.dense,
          title: Text(
            'VLC HTTP connection',
            style: Theme.of(context).textTheme.subhead,
          ),
        ),
        ListTile(
          dense: widget.settings.dense,
          title: TextField(
            controller: ipController,
            focusNode: ipFocus,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              isDense: widget.settings.dense,
              icon: Icon(Icons.computer),
              labelText: 'Host IP',
              errorText: ipDirty ? connection.ipError : null,
              helperText: prefilledIpSuffix != null &&
                      connection.ip == prefilledIpSuffix
                  ? 'Suffix pre-filled from your Wi-Fi IP'
                  : null,
            ),
          ),
        ),
        ListTile(
          dense: widget.settings.dense,
          title: TextField(
            controller: portController,
            focusNode: portFocus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              isDense: widget.settings.dense,
              icon: Icon(Icons.input),
              labelText: 'Port (default: 8080)',
              errorText: portDirty ? connection.portError : null,
            ),
          ),
        ),
        ListTile(
          dense: widget.settings.dense,
          title: TextField(
            controller: passwordController,
            focusNode: passwordFocus,
            obscureText: !showPassword,
            decoration: InputDecoration(
              isDense: widget.settings.dense,
              icon: Icon(Icons.vpn_key),
              suffixIcon: GestureDetector(
                onLongPress: () {
                  setState(() {
                    showPassword = true;
                  });
                },
                onLongPressUp: () {
                  setState(() {
                    showPassword = false;
                  });
                },
                child: Icon(Icons.remove_red_eye),
              ),
              labelText: 'Password',
              errorText: passwordDirty ? connection.passwordError : null,
            ),
          ),
        ),
        ListTile(
          dense: widget.settings.dense,
          title: RaisedButton(
            color: Theme.of(context).buttonTheme.colorScheme.primary,
            // XXX Hardcoding as theme colouring doesn't seem to be working
            textColor: Colors.white,
            onPressed: _testConnection,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                testingConnection
                    ? SizedBox(
                        width: 20.0,
                        height: 20.0,
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(Icons.school),
                const SizedBox(width: 8.0),
                Text('Test${testingConnection ? 'ing' : ''} Connection'),
              ],
            ),
          ),
        ),
        Visibility(
          visible: connectionTestResult != null,
          child: ListTile(
            dense: widget.settings.dense,
            leading: Icon(connectionTestResultIcon),
            title: Text(connectionTestResult ?? ''),
            subtitle: connectionTestResultDescription != null
                ? Text(connectionTestResultDescription)
                : null,
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
      ]),
    );
  }
}
