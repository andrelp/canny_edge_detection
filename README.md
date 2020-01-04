Small, simple and possibly faulty library which brings canny's edge detection to dart!
The input images are objects of the class "image" of the image package. 
This library can therefore be used on mobile, web and server!
Because this library cannot utilize the GPU and because it's just a very naive implementation of canny's edge detection algorithm, it's not very efficient and defenitly not ready for any real time computer vision applications! Just have some fun with it :)

## Usage


```dart
import 'package:canny_edge_detection/canny_edge_detection.dart';
import 'dart:io';
import 'package:image/image.dart';

void main() {
  Image image = decodeImage(File("input.png").readAsBytesSync());
  canny(image);
  File("output.png").writeAsBytesSync(encodePng(image));
}
```
