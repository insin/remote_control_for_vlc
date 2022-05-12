import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class EnqueueMenuGestureDetector extends StatefulWidget {
  final Widget child;
  final BrowseItem item;

  const EnqueueMenuGestureDetector(
      {Key? key, required this.child, required this.item})
      : super(key: key);

  @override
  State<EnqueueMenuGestureDetector> createState() =>
      _EnqueueMenuGestureDetectorState();
}

class _EnqueueMenuGestureDetectorState
    extends State<EnqueueMenuGestureDetector> {
  late Offset _tapPosition;

  _handleTapDown(details) {
    _tapPosition = details.globalPosition;
  }

  _showMenu() async {
    final Size size = Overlay.of(context)!.context.size!;
    var intent = await showMenu(
      context: context,
      items: <PopupMenuItem<BrowseResultIntent>>[
        const PopupMenuItem(
          value: BrowseResultIntent.play,
          child: Text('Play'),
        ),
        const PopupMenuItem(
          value: BrowseResultIntent.enqueue,
          child: Text('Enqueue'),
        ),
      ],
      position: RelativeRect.fromRect(
          _tapPosition & const Size(40, 40), Offset.zero & size),
    );
    if (intent != null) {
      if (mounted) {
        Navigator.pop(context, BrowseResult(widget.item, intent));
      }
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
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight!;
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
  return _intlStrings[enUsString]!;
}

/// Like [Iterable.join] but for lists of Widgets.
Iterable<Widget> intersperseWidgets(Iterable<Widget> iterable,
    {required Widget Function() builder}) sync* {
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
    FilteringTextInputFormatter.allow(RegExp(r'[\d.]+'));

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

  const TextAndImages({Key? key, required this.children, this.spacing = 16})
      : super(key: key);

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
