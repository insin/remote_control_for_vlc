import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum _OperatingSystem { linux, macos, windows }

Map<_OperatingSystem, String> _osNames = {
  _OperatingSystem.linux: 'Linux',
  _OperatingSystem.macos: 'macOS',
  _OperatingSystem.windows: 'Windows',
};

class VlcConfigurationGuide extends StatefulWidget {
  @override
  _VlcConfigurationGuideState createState() => _VlcConfigurationGuideState();
}

class _VlcConfigurationGuideState extends State<VlcConfigurationGuide> {
  int _currentStep = 0;
  _OperatingSystem _os;

  _onOsChanged(os) {
    setState(() {
      _os = os;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text('VLC Configuration Guide'),
            if (_os != null)
              Text('for ${_osNames[_os]}', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
      body: buildBody(),
    );
  }

  Widget buildBody() {
    var theme = Theme.of(context);
    if (_os == null) {
      return Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(24),
            child: Wrap(
              runSpacing: 16,
              children: [
                Text('Which operating system are you running VLC on?',
                    style: theme.textTheme.subtitle1),
                Column(
                    children: _OperatingSystem.values
                        .map((os) => RadioListTile(
                              title: Text(_osNames[os]),
                              value: os,
                              groupValue: _os,
                              onChanged: _onOsChanged,
                            ))
                        .toList())
              ],
            ),
          ),
        ],
      );
    }

    if (_os == _OperatingSystem.macos) {
      return buildMacStepper();
    }

    if (_os == _OperatingSystem.linux || _os == _OperatingSystem.windows) {
      return buildLinuxWindowsStepper();
    }
  }

  Widget buildLinuxWindowsStepper() {
    var theme = Theme.of(context);
    var os = _os.toString().split('.').last;
    return Stepper(
      currentStep: _currentStep,
      controlsBuilder: (BuildContext context,
          {VoidCallback onStepContinue, VoidCallback onStepCancel}) {
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: <Widget>[
              FlatButton(
                color: theme.primaryColor,
                textColor: Colors.white,
                onPressed: onStepContinue,
                child: Text(_currentStep == 2 ? 'FINISHED' : 'NEXT STEP'),
              ),
              FlatButton(
                onPressed: onStepCancel,
                child: const Text('PREVIOUS STEP'),
              ),
            ],
          ),
        );
      },
      onStepCancel: () {
        if (_currentStep > 0) {
          setState(() {
            _currentStep--;
          });
        } else {
          _onOsChanged(null);
        }
      },
      onStepContinue: () {
        if (_currentStep == 2) {
          Navigator.pop(context);
          return;
        }
        setState(() {
          _currentStep++;
        });
      },
      steps: [
        Step(
          title: Text('Enable VLC\'s web interface'),
          content: Wrap(
            runSpacing: 16,
            children: <Widget>[
              Text(
                  'In VLC\'s menu bar, select Tools > Preferences to open the preferences window:'),
              Image.asset('assets/$os-menu.png'),
              Text(
                  'Switch to Advanced Preferences mode by clicking the "All" radio button in the "Show settings" section at the bottom left of the window:'),
              Image.asset('assets/$os-show-settings.png'),
              Text(
                  'Scroll down to find the "Main interfaces" section and click it:'),
              Image.asset('assets/$os-main-interface.png'),
              Text(
                  'Check the "Web" checkbox in the "Extra interface modules" section to enable the web interface:'),
              Image.asset('assets/$os-web.png'),
            ],
          ),
        ),
        Step(
          title: Text('Set web interface password'),
          content: Wrap(
            runSpacing: 16,
            children: <Widget>[
              Text(
                  'Expand the "Main interfaces" section by clicking the ">" chevron and click the "Lua" section which appears:'),
              Image.asset('assets/$os-lua.png'),
              Text('Set a password in the "Lua HTTP" section:'),
              Image.asset('assets/$os-password.png'),
              Text(
                  'VLC Remote uses the password "vlcplayer" (without quotes) by default – if you set something else you\'ll have to manually configure the VLC connection.'),
              Text('Finally, click Save to save your changes.'),
            ],
          ),
        ),
        Step(
          title: Text('Close and restart VLC'),
          content: Row(
            children: <Widget>[
              Text('Close and restart VLC to activate the web interface.'),
            ],
          ),
        )
      ],
    );
  }

  Widget buildMacStepper() {
    var theme = Theme.of(context);
    return Stepper(
      currentStep: _currentStep,
      controlsBuilder: (BuildContext context,
          {VoidCallback onStepContinue, VoidCallback onStepCancel}) {
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: <Widget>[
              FlatButton(
                color: theme.primaryColor,
                textColor: Colors.white,
                onPressed: onStepContinue,
                child: Text(_currentStep == 1 ? 'FINISHED' : 'NEXT STEP'),
              ),
              FlatButton(
                onPressed: onStepCancel,
                child: const Text('PREVIOUS STEP'),
              ),
            ],
          ),
        );
      },
      onStepCancel: () {
        if (_currentStep > 0) {
          setState(() {
            _currentStep--;
          });
        } else {
          _onOsChanged(null);
        }
      },
      onStepContinue: () {
        if (_currentStep == 1) {
          Navigator.pop(context);
          return;
        }
        setState(() {
          _currentStep++;
        });
      },
      steps: [
        Step(
          title: Text('Enable VLC\'s web interface'),
          content: Wrap(
            runSpacing: 16,
            children: <Widget>[
              Text(
                  'In the Menubar, select VLC > Preferences to open the preferences window:'),
              Image.asset('assets/mac-menu.png'),
              Text(
                  'At the bottom of the "Interface" settings page, check "Enable HTTP web interface" and set a password.'),
              Image.asset('assets/mac-http-interface.png'),
              Text(
                  'VLC Remote uses the password "vlcplayer" (without quotes) by default – if you set something else you\'ll have to manually configure the VLC connection.'),
              Text('Finally, click Save to save your changes.'),
            ],
          ),
        ),
        Step(
          title: Text('Quit and restart VLC'),
          content: Row(
            children: <Widget>[
              Text('Quit and restart VLC to activate the web interface.'),
            ],
          ),
        )
      ],
    );
  }
}
