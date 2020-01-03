import 'dart:math' as math;
import 'package:image/image.dart';


void canny(
  Image image, {
  int blurRadius = 2,
  int lowThreshold,
  int highThreshold,
  void Function(Image image) onGrayConvertion,
  void Function(Image image) onBlur,
  void Function(Image image) onSobel,
  void Function(Image image) onNonMaxSuppressed
  }
) {
  //Convert colored image to grayscale data
  grayscale(image);
  if (onGrayConvertion!=null) onGrayConvertion(image);

  //Blur image in order to smooth out noise
  //do not blur if blurVariance is null
  if (blurRadius != null) {
    gaussianBlur(image, blurRadius);
    if (onBlur!=null) onBlur(image);
  }

  //Apply Sobel convolution on Image
  //and safe orientation of edge
  Image sobel = Image(image.width, image.height);
  Image edge_direction = Image(image.width, image.height);

  int Function(int x) clampX = (x) => x.clamp(0, image.width -1).toInt();
  int Function(int y) clampY = (y) => y.clamp(0, image.height-1).toInt();
  int Function(num p) clamp255 = (p) => p.clamp(0, 255).toInt();
  int Function(int x,int y,Image image) getSafe
   = (x,y,image) => getRed(image.getPixel(clampX(x), clampY(y)));
  
  for (var y = 0; y < image.height; ++y) {
    for (var x = 0; x < image.width; ++x) {
      int gx = - getSafe(x-1,y-1,image) - 2*getSafe(x-1,y,image) - getSafe(x-1,y+1,image)
               + getSafe(x+1,y-1,image) + 2*getSafe(x+1,y,image) + getSafe(x+1,y+1,image);
      int gy = - getSafe(x-1,y+1,image) - 2*getSafe(x,y+1,image) - getSafe(x+1,y+1,image)
               + getSafe(x-1,y-1,image) + 2*getSafe(x,y-1,image) + getSafe(x+1,y-1,image);
      int mag = clamp255(math.sqrt(gx * gx + gy * gy));
      sobel.setPixelRgba(x, y, mag, mag, mag);
      double direction = math.atan2(gy, gx);
      //convert to angle
      direction = (direction + math.pi / 2) * 180 / math.pi;
      if (direction >= 22.5 && direction < 67.5) {
        //45 deg
        edge_direction.setPixel(x, y, 45);
      } else if (direction >= 67.5 && direction < 112.5) {
        //90 deg
        edge_direction.setPixel(x, y, 90);
      } else if (direction >= 112.5 && direction < 157.5) {
        //135 deg
        edge_direction.setPixel(x, y, 135);
      } else {
        //0 deg
        edge_direction.setPixel(x, y, 0);
      }
    }
  }
  if (onSobel!=null) onSobel(sobel);

  //non-maximum suppression
  for (var y = 0; y < image.height; ++y) {
    for (var x = 0; x < image.width; ++x) {
      int p1,p2,p3,d;
      p1 = getRed(sobel.getPixel(x, y));
      d  = edge_direction.getPixel(x, y);
      if (d == 0) {
        p2 = getSafe(x-1,y,sobel);
        p3 = getSafe(x+1,y,sobel);
      } else if (d == 45) {
        p2 = getSafe(x+1,y-1,sobel);
        p3 = getSafe(x-1,y+1,sobel);
      } else if (d == 90) {
        p2 = getSafe(x,y-1,sobel);
        p3 = getSafe(x,y+1,sobel);
      } else if (d == 135) {
        p2 = getSafe(x-1,y-1,sobel);
        p3 = getSafe(x+1,y+1,sobel);
      }
      //supress value if not maximum
      if (p1 >= p2 && p1 >= p3) {
        image.setPixelRgba(x, y, p1, p1, p1);
      } else {
        image.setPixelRgba(x, y, 0, 0, 0);
      }
    }
  }
  if (onNonMaxSuppressed!=null) onNonMaxSuppressed(image);

  //Double threshold and hysteresis
  if (lowThreshold == null && highThreshold == null) {
    highThreshold = _otsusMethod(image);
    lowThreshold = highThreshold ~/ 2;
  } else if (lowThreshold == null && highThreshold != null) {
    highThreshold = highThreshold.clamp(0, 255).toInt();
    lowThreshold = highThreshold ~/ 2;
  } else if (lowThreshold != null && highThreshold == null) {
    lowThreshold = lowThreshold.clamp(0, 255).toInt();
    highThreshold = (lowThreshold * 2).clamp(0, 255).toInt();
  } else {
    lowThreshold = lowThreshold.clamp(0, 255).toInt();
    highThreshold = highThreshold.clamp(0, 255).toInt();
    if (lowThreshold > highThreshold) lowThreshold = highThreshold;
  }

  bool Function(int x, int y) shouldSuppress = (x,y) => getSafe(x,y,image) < lowThreshold;
  bool Function(int x, int y) isStrong = (x,y) => getSafe(x,y,image) >= highThreshold;

  for (var y = 0; y < image.height; ++y) {
    for (var x = 0; x < image.width; ++x) {
      if (shouldSuppress(x,y)) {
        image.setPixelRgba(x, y, 0, 0, 0);
        continue;
      } 
      if (isStrong(x,y)) {
        continue;
      }
      if (   isStrong(x-1,y-1) || isStrong(x,y-1) || isStrong(x+1,y-1) 
          || isStrong(x-1,y)   || isStrong(x+1,y)
          || isStrong(x-1,y+1) || isStrong(x,y+1) || isStrong(x+1,y+1)) {
        continue;
      }
      image.setPixelRgba(x, y, 0, 0, 0);
    }
  }

}


int _otsusMethod(Image gray) {
  //create histogramm of image gray values
  List<int> histogramm = List.filled(256, 0);
  for (var y = 0; y < gray.height; ++y) {
    for (var x = 0; x < gray.width; ++x) {
      histogramm[getRed(gray.getPixel(x, y))]++;
    }
  }

  int threshold = 0;
  double sigma_b;

  int w0,w1;
  double m0,m1;
  w0 = gray.width * gray.height;
  w1 = 0;

  //exhaustive search which threshold candidate maximizes
  //inter class variance
  for (var t = 0; t < 256; ++t) {
    w0 -= histogramm[t];
    w1 += histogramm[t];
    m0 = 0; m1 = 0;
    for (var i = 1; i <= t; ++i) {
      m0 += i * histogramm[i];
    }
    m0 /= w0;
    for (var i = t+1; i < 256; ++i) {
      m1 += i * histogramm[i];
    }
    m1 /= w1;

    double sigma_b_new = w0*w1*math.pow(m0-m1, 2);
    if (sigma_b == null || sigma_b_new > sigma_b) {
      threshold = t;
      sigma_b = sigma_b_new;
    }
  }
  print("threshld of $threshold");
  return threshold;
}