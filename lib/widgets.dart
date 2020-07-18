import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class EnqueueMenuGestureDetector extends StatefulWidget {
  final Widget child;
  final BrowseItem item;

  EnqueueMenuGestureDetector({@required this.child, @required this.item});

  @override
  _EnqueueMenuGestureDetectorState createState() =>
      _EnqueueMenuGestureDetectorState();
}

class _EnqueueMenuGestureDetectorState
    extends State<EnqueueMenuGestureDetector> {
  Offset _tapPosition;

  _handleTapDown(details) {
    _tapPosition = details.globalPosition;
  }

  _showMenu() async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject();
    var intent = await showMenu(
      context: context,
      items: <PopupMenuItem<BrowseResultIntent>>[
        PopupMenuItem(
          child: Text('Play'),
          value: BrowseResultIntent.play,
        ),
        PopupMenuItem(
          child: Text('Enqueue'),
          value: BrowseResultIntent.enqueue,
        ),
      ],
      position: RelativeRect.fromRect(
          _tapPosition & Size(40, 40), Offset.zero & overlay.size),
    );
    if (intent != null) {
      Navigator.pop(context, BrowseResult(widget.item, intent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onLongPress: _showMenu,
      child: widget.child,
    );
  }
}

/// A custom track shape for a [Slider] which lets it go full-width.
///
/// From https://github.com/flutter/flutter/issues/37057#issuecomment-516048356
class FullWidthTrackShape extends RoundedRectSliderTrackShape {
  Rect getPreferredRect({
    @required RenderBox parentBox,
    Offset offset = Offset.zero,
    @required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

var _intlStrings = {
  'Equalizer': 'Equaliser',
  'Settings': 'Settings',
};

String intl(String enUsString) {
  if (ui.window.locale.countryCode == 'US' ||
      !_intlStrings.containsKey(enUsString)) {
    return enUsString;
  }
  return _intlStrings[enUsString];
}

/// Like [Iterable.join] but for lists of Widgets.
Iterable<Widget> intersperseWidgets(Iterable<Widget> iterable,
    {Widget Function() builder}) sync* {
  final iterator = iterable.iterator;
  if (iterator.moveNext()) {
    yield iterator.current;
    while (iterator.moveNext()) {
      yield builder();
      yield iterator.current;
    }
  }
}

/// A [WhitelistingTextInputFormatter] that takes in digits `[0-9]` and periods
/// `.` only.
var ipWhitelistingTextInputFormatter =
    WhitelistingTextInputFormatter(RegExp(r'[\d.]+'));

/// Remove current focus to hide the keyboard.
removeCurrentFocus(BuildContext context) {
  FocusScopeNode currentFocus = FocusScope.of(context);
  if (!currentFocus.hasPrimaryFocus) {
    currentFocus.unfocus();
  }
}

class TextAndImages extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  TextAndImages({@required this.children, this.spacing = 16});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: intersperseWidgets(
        children.map((child) => Row(children: [
              Expanded(
                  child: Container(
                alignment: Alignment.topLeft,
                child: child,
              ))
            ])),
        builder: () => SizedBox(height: spacing),
      ).toList(),
    );
  }
}
