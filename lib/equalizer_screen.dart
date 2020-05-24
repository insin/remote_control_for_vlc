import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

var _frequencies = [
  '60Hz',
  '170Hz',
  '310Hz',
  '600Hz',
  '1KHz',
  '3KHz',
  '6KHz',
  '12KHz',
  '14KHz',
  '16KHz'
];

class EqualizerScreen extends StatefulWidget {
  final Equalizer equalizer;
  final Stream<Equalizer> equalizerStream;
  final Function(bool enabled) onToggleEnabled;
  final Function(int presetId) onPresetChange;
  final Function(String db) onPreampChange;
  final Function(int bandId, String db) onBandChange;

  EqualizerScreen({
    this.equalizer,
    this.equalizerStream,
    this.onToggleEnabled,
    this.onPresetChange,
    this.onPreampChange,
    this.onBandChange,
  });

  @override
  _EqualizerScreenState createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  Equalizer _equalizer;
  StreamSubscription _equalizerSubscription;
  Preset _preset;
  double _preamp;

  bool _snapBands = true;
  int _draggingBand;
  Equalizer _draggingEqualizer;
  double _dragStartValue;
  double _dragValue;

  @override
  void initState() {
    _equalizer = widget.equalizer;
    _equalizerSubscription = widget.equalizerStream.listen(_onEqualizer);
    super.initState();
  }

  @override
  void dispose() {
    _equalizerSubscription.cancel();
    super.dispose();
  }

  _choosePreset() async {
    var preset = await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Preset'),
        children: _equalizer.presets
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

  _onEqualizer(Equalizer equalizer) {
    if (equalizer == null) {
      Navigator.pop(context);
      return;
    }
    this.setState(() {
      if (_preamp != null &&
          _decibelsToString(_equalizer.preamp) != _decibelsToString(_preamp) &&
          _decibelsToString(equalizer.preamp) == _decibelsToString(_preamp)) {
        _preamp = null;
      }
      if (_draggingBand == null &&
          _draggingEqualizer != null &&
          _draggingEqualizer.bands.every((band) =>
              _decibelsToString(band.value) ==
              _decibelsToString(equalizer.bands[band.id].value))) {
        _draggingEqualizer = null;
      }
      _equalizer = equalizer;
    });
  }

  double _getBandValue(int band) {
    // Not dragging, use the current value
    // If we finished changing a band, use the new values until they're current
    if (_draggingBand == null) {
      return (_draggingEqualizer ?? _equalizer).bands[band].value;
    }
    // The dragging band always uses the drag value
    if (band == _draggingBand) {
      return _dragValue;
    }
    // If we're not snapping, other bands use the current value
    if (!_snapBands) {
      return _equalizer.bands[band].value;
    }
    // Otherwise add portions of the size of the change to neighbouring bands
    var distance = (band - _draggingBand).abs();
    switch (distance) {
      case 1:
        return (_draggingEqualizer.bands[band].value +
                ((_dragValue - _dragStartValue) / 2))
            .clamp(-20.0, 20.0);
      case 2:
        return (_draggingEqualizer.bands[band].value +
                ((_dragValue - _dragStartValue) / 8))
            .clamp(-20.0, 20.0);
      case 3:
        return (_draggingEqualizer.bands[band].value +
                ((_dragValue - _dragStartValue) / 40))
            .clamp(-20.0, 20.0);
      default:
        return _equalizer.bands[band].value;
    }
  }

  _onBandChangeStart(int band, double value) {
    setState(() {
      _draggingEqualizer = _equalizer;
      _draggingBand = band;
      _dragStartValue = value;
      _dragValue = value;
    });
  }

  _onBandChanged(double value) {
    setState(() {
      _dragValue = value;
    });
  }

  _onBandChangeEnd(double value) {
    List<Band> bandChanges = [];
    if (!_snapBands) {
      _draggingEqualizer.bands[_draggingBand].value = value;
      bandChanges.add(Band(_draggingBand, value));
    } else {
      for (int band = math.max(0, _draggingBand - 3);
          band < math.min(_frequencies.length, _draggingBand + 4);
          band++) {
        var value = _getBandValue(band);
        // Store new values to display while VLC status catches up
        _draggingEqualizer.bands[band].value = value;
        bandChanges.add(Band(band, value));
      }
    }
    setState(() {
      _draggingBand = null;
      _dragStartValue = null;
      _dragValue = null;
    });
    SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
      bandChanges.forEach((band) =>
          widget.onBandChange(band.id, _decibelsToString(band.value)));
    });
  }

  _updateBands(int band, double value) {}

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(intl('Equalizer')),
      ),
      body: ListView(children: [
        SwitchListTile(
          title: Text('Enable', textAlign: TextAlign.right),
          value: _equalizer.enabled,
          onChanged: widget.onToggleEnabled,
        ),
        if (_equalizer.enabled)
          Column(children: [
            ListTile(
              title: Text('Preset'),
              subtitle: Text(_preset?.name ?? 'Tap to select'),
              onTap: _choosePreset,
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Text('Preamp', style: theme.textTheme.subtitle1),
                  SizedBox(width: 16),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackShape: FullWidthTrackShape(),
                      ),
                      child: Slider(
                        max: 20,
                        min: -20,
                        value: _preamp ?? _equalizer.preamp,
                        onChanged: (db) {
                          setState(() {
                            _preamp = db;
                          });
                          Throttle.milliseconds(333, widget.onPreampChange,
                              [_decibelsToString(db)]);
                        },
                        onChangeEnd: (preamp) {
                          widget.onPreampChange(_decibelsToString(preamp));
                        },
                      ),
                    ),
                  )
                ],
              ),
            ),
            SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (int i = 0; i < _frequencies.length; i++)
                _VerticalBandSlider(
                  label: _frequencies[i],
                  band: i,
                  value: _getBandValue(i),
                  onChangeStart: _onBandChangeStart,
                  onChanged: _onBandChanged,
                  onChangeEnd: _onBandChangeEnd,
                ),
            ]),
            SwitchListTile(
              title: Text('Snap bands', textAlign: TextAlign.right),
              value: _snapBands,
              onChanged: (snapBands) {
                setState(() {
                  _snapBands = snapBands;
                });
              },
            ),
          ]),
      ]),
    );
  }
}

class _VerticalBandSlider extends StatefulWidget {
  final String label;
  final int band;
  final double value;
  final Function(int band, double value) onChangeStart;
  final Function(double value) onChanged;
  final Function(double value) onChangeEnd;

  _VerticalBandSlider({
    this.label,
    this.band,
    this.value,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  _VerticalBandSliderState createState() => _VerticalBandSliderState();
}

class _VerticalBandSliderState extends State<_VerticalBandSlider> {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('+20dB', style: TextStyle(fontSize: 10)),
      SizedBox(height: 16),
      RotatedBox(
        quarterTurns: -1,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: FullWidthTrackShape(),
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            max: 20,
            min: -20,
            value: widget.value,
            onChangeStart: (value) {
              widget.onChangeStart(widget.band, value);
            },
            onChanged: (value) {
              widget.onChanged(value);
            },
            onChangeEnd: (value) {
              widget.onChangeEnd(value);
            },
          ),
        ),
      ),
      SizedBox(height: 16),
      Text('-20dB', style: TextStyle(fontSize: 10)),
      SizedBox(height: 8),
      Text(widget.label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    ]);
  }
}
