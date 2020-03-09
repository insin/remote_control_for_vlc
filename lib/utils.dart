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

/*
 * Trick stolen from https://gist.github.com/shubhamjain/9809108#file-vlc_http-L108
 * The interface expects value between 0 and 512 while in the UI it is 0% to 200%.
 * So a factor of 2.56 is used to convert 0% to 200% to a scale of 0 to 512.
 */
const VolumeSliderScaleFactor = 2.56;