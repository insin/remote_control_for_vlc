import 'package:flutter/material.dart';

import 'models.dart';
import 'widgets.dart';

class VlcConfigurationGuide extends StatefulWidget {
  const VlcConfigurationGuide({Key? key}) : super(key: key);

  @override
  State<VlcConfigurationGuide> createState() => _VlcConfigurationGuideState();
}

class _VlcConfigurationGuideState extends State<VlcConfigurationGuide> {
  int _currentStep = 0;
  OperatingSystem? _os;

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
            const Text('VLC Configuration Guide'),
            if (_os != null)
              Text('for ${osNames[_os]}', style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
      body: buildBody(),
    );
  }

  Widget buildBody() {
    switch (_os) {
      case OperatingSystem.macos:
        return buildMacStepper();
      case OperatingSystem.linux:
      case OperatingSystem.windows:
        return buildLinuxWindowsStepper();
      default:
        var theme = Theme.of(context);
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(24),
              child: Wrap(
                runSpacing: 16,
                children: [
                  Text('Which operating system are you running VLC on?',
                      style: theme.textTheme.subtitle1),
                  Column(
                      children: OperatingSystem.values
                          .map((os) => RadioListTile(
                                title: Text(osNames[os]!),
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
  }

  Widget buildLinuxWindowsStepper() {
    var theme = Theme.of(context);
    var os = _os.toString().split('.').last;
    return Stepper(
      currentStep: _currentStep,
      controlsBuilder: (BuildContext context, ControlsDetails details) {
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: <Widget>[
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  primary: Colors.white,
                ),
                onPressed: details.onStepContinue,
                child: Text(_currentStep == 2 ? 'FINISHED' : 'NEXT STEP'),
              ),
              TextButton(
                onPressed: details.onStepCancel,
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
          title: const Text('Enable VLC\'s web interface'),
          content: TextAndImages(
            children: <Widget>[
              const Text(
                  'In VLC\'s menu bar, select Tools > Preferences to open the preferences window:'),
              Image.asset('assets/$os-menu.png'),
              const Text(
                  'Switch to Advanced Preferences mode by clicking the "All" radio button in the "Show settings" section at the bottom left of the window:'),
              Image.asset('assets/$os-show-settings.png'),
              const Text(
                  'Scroll down to find the "Main interfaces" section and click it:'),
              Image.asset('assets/$os-main-interface.png'),
              const Text(
                  'Check the "Web" checkbox in the "Extra interface modules" section to enable the web interface:'),
              Image.asset('assets/$os-web.png'),
            ],
          ),
        ),
        Step(
          title: const Text('Set web interface password'),
          content: TextAndImages(
            children: <Widget>[
              const Text(
                  'Expand the "Main interfaces" section by clicking the ">" chevron and click the "Lua" section which appears:'),
              Image.asset('assets/$os-lua.png'),
              const Text('Set a password in the "Lua HTTP" section:'),
              Image.asset('assets/$os-password.png'),
              const Text(
                  'Remote Control for VLC uses the password "vlcplayer" (without quotes) by default – if you set something else you\'ll have to manually configure the VLC connection.'),
              const Text('Finally, click Save to save your changes.'),
            ],
          ),
        ),
        Step(
          title: const Text('Close and restart VLC'),
          content: Row(
            children: const <Widget>[
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
      controlsBuilder: (BuildContext context, ControlsDetails details) {
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: <Widget>[
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  primary: Colors.white,
                ),
                onPressed: details.onStepContinue,
                child: Text(_currentStep == 1 ? 'FINISHED' : 'NEXT STEP'),
              ),
              TextButton(
                onPressed: details.onStepCancel,
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
          title: const Text('Enable VLC\'s web interface'),
          content: TextAndImages(
            children: <Widget>[
              const Text(
                  'In the Menubar, select VLC > Preferences to open the preferences window:'),
              Image.asset('assets/mac-menu.png'),
              const Text(
                  'At the bottom of the "Interface" settings page, check "Enable HTTP web interface" and set a password.'),
              Image.asset('assets/mac-http-interface.png'),
              const Text(
                  'Remote Control for VLC uses the password "vlcplayer" (without quotes) by default – if you set something else you\'ll have to manually configure the VLC connection.'),
              const Text('Finally, click Save to save your changes.'),
            ],
          ),
        ),
        Step(
          title: const Text('Quit and restart VLC'),
          content: Row(
            children: const <Widget>[
              Text('Quit and restart VLC to activate the web interface.'),
            ],
          ),
        )
      ],
    );
  }
}
