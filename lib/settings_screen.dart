import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

    ipController.text = widget.settings.connection.ip;
    portController.text = widget.settings.connection.port;
    passwordController.text = widget.settings.connection.password;

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

    if (widget.settings.connection.ip == '') {
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

    try {
      var response = await http.get(
          Uri.http(
            '${ipController.text}:${portController.text}',
            '/requests/status.xml',
          ),
          headers: {
            'Authorization': 'Basic ' +
                base64Encode(utf8.encode(':${passwordController.text}'))
          }).timeout(Duration(seconds: 2));

      if (response.statusCode == 200) {
        widget.settings.connection = connection;
        widget.onSettingsChanged();
        result = 'Connection successful';
        description = 'Connection settings saved';
        icon = Icons.check;
      } else {
        icon = Icons.error;
        if (response.statusCode == 401) {
          result = 'Password is invalid';
          description = 'Press and hold the eye icon to check your password';
        } else {
          result = 'Unexpected response';
          description = 'Status code: ${response.statusCode}';
        }
      }
    } catch (e) {
      description = 'Check the IP and port settings';
      icon = Icons.error;
      if (e is TimeoutException) {
        result = 'Connection timed out';
      } else if (e is SocketException) {
        result = 'Connection error';
      } else {
        result = 'Connection error: ${e.runtimeType}';
      }
    }

    setState(() {
      connectionTestResult = result;
      connectionTestResultDescription = description;
      connectionTestResultIcon = icon;
      testingConnection = false;
    });
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
            'VLC connection',
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
                onTap: () {
                  setState(() {
                    showPassword = !showPassword;
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
            onPressed: !testingConnection ? _testConnection : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.network_check),
                const SizedBox(width: 8.0),
                Text('Test Connection'),
              ],
            ),
          ),
        ),
        Visibility(
          visible: testingConnection || connectionTestResult != null,
          child: ListTile(
            dense: widget.settings.dense,
            leading: testingConnection
                ? SizedBox(
                    width: 20.0,
                    height: 20.0,
                    child: CircularProgressIndicator(),
                  )
                : Icon(
                    connectionTestResultIcon,
                    color: connectionTestResultIcon == Icons.check
                        ? Colors.green
                        : Colors.redAccent,
                  ),
            title: Text(testingConnection
                ? 'Testing connection...'
                : connectionTestResult ?? ''),
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
