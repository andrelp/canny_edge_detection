import 'package:canny_edge_detection/canny_edge_detection.dart';
import 'dart:io';
import 'package:image/image.dart';

void Function(Image image) safeImageCallBack(String outname) {
  return (image) => File(outname).writeAsBytesSync(encodePng(image));;
}

void main() {
  Image image = decodeImage(File("test_A.png").readAsBytesSync());
  canny(
    image,
    blurRadius: 1,
    onBlur: safeImageCallBack("test_B.png"),
    onGrayConvertion: safeImageCallBack("test_A.png"),
    onSobel: safeImageCallBack("test_C.png"),
    onNonMaxSuppressed: safeImageCallBack("test_D.png")
  );
  File("test_E.png").writeAsBytesSync(encodePng(image));
}
