import 'package:image/image.dart' as img; void main() { var i = img.Image(width: 10, height: 10, numChannels: 3); var i2 = i.convert(numChannels: 4); print(i2.numChannels); }
