import 'package:flutter/material.dart';

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

/// Remove current focus to hide the keyboard.
removeCurrentFocus(BuildContext context) {
  FocusScopeNode currentFocus = FocusScope.of(context);
  if (!currentFocus.hasPrimaryFocus) {
    currentFocus.unfocus();
  }
}
