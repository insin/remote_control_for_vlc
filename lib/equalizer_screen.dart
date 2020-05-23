import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_throttle_it/just_throttle_it.dart';

import 'models.dart';
import 'widgets.dart';

String _decibelsToString(double db) {
  var string = db.toStringAsFixed(1);
  if (string == '-0.0') {
    string = '0.0';
  }
  return string;
}

class EqualizerScreen extends StatefulWidget {
  final Equalizer state;
  final Stream<Equalizer> states;
  final Function(bool enabled) onToggleEnabled;
  final Function(int presetId) onPresetChange;
  final Function(String db) onPreampChange;
  final Function(int bandId, String db) onBandChange;

  EqualizerScreen({
    this.state,
    this.states,
    this.onToggleEnabled,
    this.onPresetChange,
    this.onPreampChange,
    this.onBandChange,
  });

  @override
  _EqualizerScreenState createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  Equalizer _state;
  StreamSubscription _statesSubscription;
  Preset _preset;
  double _preamp;

  @override
  void initState() {
    _state = widget.state;
    _statesSubscription = widget.states.listen(_onLatestState);
    super.initState();
  }

  @override
  void dispose() {
    _statesSubscription.cancel();
    super.dispose();
  }

  _choosePreset() async {
    var preset = await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Preset'),
        children: _state.presets
            .map((preset) => SimpleDialogOption(
                  child: Text(preset.name),
                  onPressed: () {
                    Navigator.pop(context, preset);
                  },
                ))
            .toList(),
      ),
    );
    if (preset != null) {
      setState(() {
        _preset = preset;
      });
      widget.onPresetChange(preset.id);
    }
  }

  _onLatestState(Equalizer newState) {
    if (newState == null) {
      Navigator.pop(context);
      return;
    }
    this.setState(() {
      if (_preamp != null &&
          _decibelsToString(_state.preamp) != _decibelsToString(_preamp) &&
          _decibelsToString(newState.preamp) == _decibelsToString(_preamp)) {
        _preamp = null;
      }
      _state = newState;
    });
  }

  String get _preampLabel => _decibelsToString(_preamp ?? _state.preamp);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(intl('Equalizer')),
      ),
      body: ListView(children: [
        SwitchListTile(
          title: Text('Enable'),
          value: _state.enabled,
          onChanged: widget.onToggleEnabled,
        ),
        if (_state.enabled)
          Column(children: [
            ListTile(
              title: Text('Preset'),
              subtitle: Text(_preset?.name ?? 'Tap to select'),
              onTap: _choosePreset,
            ),
            ListTile(
              title: Text('Preamp'),
              subtitle: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackShape: FullWidthTrackShape(),
                ),
                child: Slider(
                  max: 20,
                  min: -20,
                  value: _preamp ?? _state.preamp,
                  onChanged: (db) {
                    setState(() {
                      _preamp = db;
                    });
                    Throttle.milliseconds(
                        333, widget.onPreampChange, [_decibelsToString(db)]);
                  },
                  onChangeEnd: (preamp) {
                    widget.onPreampChange(_decibelsToString(preamp));
                  },
                ),
              ),
              trailing: Padding(
                  padding: EdgeInsets.only(top: 23),
                  child: Text('$_preampLabel dB')),
            ),
            ListTile(
              title: Text('Low End EQ'),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _VerticalBandSlider(
                  label: '60 Hz',
                  band: _state.bands[0],
                  onBandChange: widget.onBandChange),
              _VerticalBandSlider(
                  label: '170 Hz',
                  band: _state.bands[1],
                  onBandChange: widget.onBandChange),
              _VerticalBandSlider(
                  label: '310 Hz',
                  band: _state.bands[2],
                  onBandChange: widget.onBandChange),
              _VerticalBandSlider(
                  label: '600 Hz',
                  band: _state.bands[3],
                  onBandChange: widget.onBandChange),
              _VerticalBandSlider(
                  label: '1 KHz',
                  band: _state.bands[4],
                  onBandChange: widget.onBandChange),
            ]),
            ListTile(
              title: Text('High End EQ'),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _VerticalBandSlider(
                  label: '3 KHz',
                  band: _state.bands[5],
                  onBandChange: widget.onBandChange),
              _VerticalBandSlider(
                  label: '6 KHz',
                  band: _state.bands[6],
                  onBandChange: widget.onBandChange),
              _VerticalBandSlider(
                  label: '12 KHz',
                  band: _state.bands[7],
                  onBandChange: widget.onBandChange),
              _VerticalBandSlider(
                  label: '14 KHz',
                  band: _state.bands[8],
                  onBandChange: widget.onBandChange),
              _VerticalBandSlider(
                  label: '16 KHz',
                  band: _state.bands[9],
                  onBandChange: widget.onBandChange),
            ]),
            SizedBox(height: 32)
          ]),
      ]),
    );
  }
}

class _VerticalBandSlider extends StatefulWidget {
  final Band band;
  final String label;
  final Function(int bandId, String db) onBandChange;

  _VerticalBandSlider({this.label, this.band, this.onBandChange});

  @override
  _VerticalBandSliderState createState() => _VerticalBandSliderState();
}

class _VerticalBandSliderState extends State<_VerticalBandSlider> {
  double _value;

  @override
  void didUpdateWidget(_VerticalBandSlider oldWidget) {
    if (_value != null &&
        _decibelsToString(oldWidget.band.value) != _decibelsToString(_value) &&
        _decibelsToString(widget.band.value) == _decibelsToString(_value)) {
      setState(() {
        _value = null;
      });
    }
    super.didUpdateWidget(oldWidget);
  }

  String get _label => _decibelsToString(_value ?? widget.band.value);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      RotatedBox(
        quarterTurns: -1,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: FullWidthTrackShape(),
          ),
          child: Slider(
            max: 20,
            min: -20,
            value: _value ?? widget.band.value,
            onChanged: (db) {
              setState(() {
                _value = db;
              });
              Throttle.milliseconds(333, widget.onBandChange,
                  [widget.band.id, _decibelsToString(db)]);
            },
            onChangeEnd: (db) {
              widget.onBandChange(widget.band.id, _decibelsToString(db));
            },
          ),
        ),
      ),
      SizedBox(height: 10),
      Text(widget.label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text('$_label dB', style: TextStyle(fontSize: 12))
    ]);
  }
}
