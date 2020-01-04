/// This library exposed a function canny, which applies 
/// cannys edge detection algorithm on images.
/// For image inputs, this library used the image package
/// which intern does not rely on dart:io, so it can be
/// used for server, web, console or flutter!
library canny_edge_detection;

export 'src/canny.dart';

