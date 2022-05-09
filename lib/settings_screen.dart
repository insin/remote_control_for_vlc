import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'host_ip_guide.dart';
import 'models.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  final Settings settings;
  final Function onSettingsChanged;

  const SettingsScreen(
      {Key? key, required this.settings, required this.onSettingsChanged})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Connection connection = Connection();
  var ipController = TextEditingController();
  var ipFocus = FocusNode();
  bool ipDirty = false;
  var portController = TextEditingController();
  var portFocus = FocusNode();
  bool portDirty = false;
  var passwordController = TextEditingController();
  var passwordFocus = FocusNode();
  bool passwordDirty = false;

  String? prefilledIpSuffix;
  bool showPassword = false;

  bool scanningNetwork = false;

  bool testingConnection = false;
  String? connectionTestResult;
  String? connectionTestResultDescription;
  IconData? connectionTestResultIcon;

  @override
  initState() {
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
      var ip = await NetworkInfo().getWifiIP();
      if (ip != null) {
        setState(() {
          prefilledIpSuffix = ip.substring(0, ip.lastIndexOf('.') + 1);
          ipController.text = prefilledIpSuffix!;
        });
      }
    }
  }

  _testConnection() async {
    removeCurrentFocus(context);
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
          }).timeout(const Duration(seconds: 2));

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
          description = 'Tap the eye icon to check your password';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headingStyle = theme.textTheme.subtitle1!
        .copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Settings'),
      ),
      body: ListView(children: <Widget>[
        ListTile(
          dense: widget.settings.dense,
          title: Text(
            'VLC connection',
            style: headingStyle,
          ),
        ),
        ListTile(
          dense: widget.settings.dense,
          title: TextField(
            controller: ipController,
            focusNode: ipFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ipWhitelistingTextInputFormatter],
            decoration: InputDecoration(
              isDense: widget.settings.dense,
              icon: const Icon(Icons.computer),
              labelText: 'Host IP',
              errorText: ipDirty ? connection.ipError : null,
              helperText: prefilledIpSuffix != null &&
                      connection.ip == prefilledIpSuffix
                  ? 'Suffix pre-filled from your Wi-Fi IP'
                  : null,
            ),
          ),
          trailing: IconButton(
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const HostIpGuide()));
            },
            tooltip: 'Get help finding your IP',
            icon: Icon(Icons.help, color: theme.primaryColor),
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
              icon: const Icon(Icons.vpn_key),
              labelText: 'Password',
              errorText: passwordDirty ? connection.passwordError : null,
            ),
          ),
          trailing: IconButton(
            onPressed: () {
              setState(() {
                showPassword = !showPassword;
              });
            },
            tooltip: 'Toggle password visibility',
            icon: Icon(Icons.remove_red_eye,
                color: showPassword ? theme.primaryColor : null),
          ),
        ),
        ListTile(
          dense: widget.settings.dense,
          title: TextField(
            controller: portController,
            focusNode: portFocus,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
                isDense: widget.settings.dense,
                icon: const Icon(Icons.input),
                labelText: 'Port (default: 8080)',
                errorText: portDirty ? connection.portError : null,
                helperText: 'Advanced use only'),
          ),
        ),
        ListTile(
          dense: widget.settings.dense,
          title: ElevatedButton(
            style: ElevatedButton.styleFrom(
              primary: theme.buttonTheme.colorScheme!.primary,
              onPrimary: Colors.white,
            ),
            onPressed: !testingConnection ? _testConnection : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                testingConnection
                    ? const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white)),
                        ),
                      )
                    : const Icon(Icons.network_check),
                const SizedBox(width: 8.0),
                const Text('Test & Save Connection'),
              ],
            ),
          ),
        ),
        if (connectionTestResult != null)
          ListTile(
            dense: widget.settings.dense,
            leading: Icon(
              connectionTestResultIcon,
              color: connectionTestResultIcon == Icons.check
                  ? Colors.green
                  : Colors.redAccent,
            ),
            title: Text(connectionTestResult!),
            subtitle: connectionTestResultDescription != null
                ? Text(connectionTestResultDescription!)
                : null,
          ),
        const Divider(),
        ListTile(
          dense: widget.settings.dense,
          title: Text(
            'Display options',
            style: headingStyle,
          ),
        ),
        CheckboxListTile(
          title: const Text('Compact display'),
          value: widget.settings.dense,
          dense: widget.settings.dense,
          onChanged: (dense) {
            setState(() {
              widget.settings.dense = dense ?? false;
              widget.onSettingsChanged();
            });
          },
        ),
        CheckboxListTile(
          title: const Text('Blurred cover background'),
          subtitle: const Text('When available for audio files'),
          value: widget.settings.blurredCoverBg,
          dense: widget.settings.dense,
          onChanged: (dense) {
            setState(() {
              widget.settings.blurredCoverBg = dense ?? false;
              widget.onSettingsChanged();
            });
          },
        ),
      ]),
    );
  }
}
