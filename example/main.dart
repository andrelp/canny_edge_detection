import 'package:canny_edge_detection/canny_edge_detection.dart';
import 'dart:io';
import 'package:image/image.dart';

void Function(Image image) safeImageCallBack(String outname) {
  return (image) => File(outname).writeAsBytesSync(encodePng(image));;
}

void main() {
  Image image = decodeImage(File("test_input.png").readAsBytesSync());
  canny(
    image,
    blurRadius: 2,
    onGrayConvertion: safeImageCallBack("test_outputA.png"),
    onBlur: safeImageCallBack("test_outputB.png"),
    onSobel: safeImageCallBack("test_outputC.png"),
    onNonMaxSuppressed: safeImageCallBack("test_outputD.png")
  );
  File("test_outputEndResult.png").writeAsBytesSync(encodePng(image));
}

