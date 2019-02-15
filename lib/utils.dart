var _dot = new RegExp(r'\.');

String dotsToSpaces(String s, {bool keepExt = false}) {
  String ext;
  var parts = s.split(_dot);
  if (keepExt) {
    ext = parts.removeLast();
  }
  return parts.join(' ') + (keepExt ? '.$ext' : '');
}

String formatTime(Duration duration) {
  String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '${duration.inHours >= 1 ? duration.inHours.toString() + ':' : ''}$minutes:$seconds';
}
