import 'dart:collection';
import 'dart:math' as math;
import 'package:image/image.dart';

class Index2d {
  final int x, y;
  const Index2d(this.x,this.y);

  @override
  bool operator == (dynamic other) => other is Index2d && other.x == x && other.y == y;
  @override
  int get hashCode => x.hashCode | y.hashCode;
}

Set<Set<Index2d>> canny(
  Image image, {
  int blurRadius = 2,
  int lowThreshold,
  int highThreshold,
  void Function(Image image) onGrayConvertion,
  void Function(Image image) onBlur,
  void Function(Image image) onSobel,
  void Function(Image image) onNonMaxSuppressed,
  void Function(Image image) onImageResult,
  }
) {
  //<Convert colored image to grayscale data>
  grayscale(image);
  if (onGrayConvertion!=null) onGrayConvertion(image);

  //<Blur image in order to smooth out noise>
  //do not blur if blurVariance is null
  if (blurRadius != null) {
    gaussianBlur(image, blurRadius);
    if (onBlur!=null) onBlur(image);
  }

  //<Apply Sobel convolution on Image>
  //and safe orientation of edges
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
      //0 degrees describes a vertical edge and with
      //increasing degrees the edge is going counter-clockwise
    }
  }
  if (onSobel!=null) onSobel(sobel);

  //helper function to determine neighbours of an edge
  Set<Index2d> Function(int x, int y) getNeighbours = (x,y) {
    int direction = edge_direction.getPixel(x, y);
    Set<Index2d> nei = Set();
    switch(direction) {
      case 0:
        if (y > 0) nei.add(Index2d(x,y-1));
        if (y < image.height-1) nei.add(Index2d(x,y+1));
        break;
      case 45:
        if (x > 0 && y > 0) nei.add(Index2d(x-1,y-1));
        if (x < image.width-1 && y < image.height-1) nei.add(Index2d(x+1,y+1));
        break;
      case 90:
        if (x > 0) nei.add(Index2d(x-1,y));
        if (x < image.width-1) nei.add(Index2d(x+1,y));
        break;
      case 135:
        if (y > 0 && x < image.width-1) nei.add(Index2d(x+1,y-1));
        if (x > 0 && y < image.height-1) nei.add(Index2d(x-1,y+1));
        break;
    }
    return nei;
  };

  //<non-maximum suppression>
  for (var y = 0; y < image.height; ++y) {
    for (var x = 0; x < image.width; ++x) {
      int p = getRed(sobel.getPixel(x, y));
      Set<Index2d> nei = getNeighbours(x,y);
      int max = nei.fold(p, (t,i) {
        int pnew = getRed(sobel.getPixel(i.x, i.y));
        return t > pnew ? t : pnew;
      });
      //supress value if not maximum
      if (max > p) {
        image.setPixelRgba(x, y, 0, 0, 0);
      } else {
        image.setPixelRgba(x, y, p, p, p);
      }
    }
  }
  if (onNonMaxSuppressed!=null) onNonMaxSuppressed(image);

  //<Double threshold and hysteresis>
  //first determine threshold values
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

  //hysteresis by blob analysis
  bool Function(int x, int y) isWeak = (x,y) => getSafe(x,y,image) >= lowThreshold;
  bool Function(int x, int y) isStrong = (x,y) => getSafe(x,y,image) >= highThreshold;
  Set<Set<Index2d>> edges = Set();
  Set<Index2d> nonEdges = Set();
  int currentLabel = 2;
  ListQueue<Index2d> currentBlobNeighbours = ListQueue();
  Image labeledPixels = Image(image.width, image.height);

  //a pixel which is neither weak or strong is considered background and is labeled 1
  //a pixel which is at least weak is consideres foreground and is labeled with the 
  //same label as all pixels it is connected to along its edge direction
  //a background label will be supressed and a foreground label will not be suppressed
  //if and only if it is in the same region (same label) as a strong edge
  for (var y = 0; y < image.height; ++y) {
    for (var x = 0; x < image.width; ++x) {
      //if current pixel is not weak, label it with 1
      if (!isWeak(x,y)) {
        //pixel is background
        labeledPixels.setPixel(x, y, 1);
        image.setPixelRgba(x, y, 0, 0, 0);
        continue;
      }
      if (labeledPixels.getPixel(x, y) != 0) {
        //pixel was already labeled
        continue;
      }
      //pixel is an unlabeled foreground edge
      currentBlobNeighbours.addLast(Index2d(x, y));
      bool isStrongEdge = false;
      Set<Index2d> currentEdge = Set();
      while (currentBlobNeighbours.isNotEmpty) {
        Index2d w = currentBlobNeighbours.removeLast();
        currentEdge.add(w);
        if (isStrong(w.x,w.y)) {
          isStrongEdge = true;
        }
        labeledPixels.setPixel(w.x, w.y, currentLabel);
        //get all neighbours of pixel at (w.x,w.y)
        //a neighbour of a pixel A is one of the two 
        //pixels along the edge direction of A OR a
        //pixel B for which A is a pixel along B's
        //edge direction!
        //if a neighbour is a foreground pixel and
        //not already labelled put it in Queue
        Set<Index2d> symmetricNeighbours = Set();
        symmetricNeighbours.addAll(getNeighbours(w.x,w.y));
        if (w.x > 0 && w.y > 0 && getNeighbours(w.x-1,w.y-1).contains(w)) {
          symmetricNeighbours.add(Index2d(w.x-1,w.y-1));
        }
        if (w.y > 0 && getNeighbours(w.x,w.y-1).contains(w)) {
          symmetricNeighbours.add(Index2d(w.x,w.y-1));
        }
        if (w.x < image.width-1 && w.y > 0 && getNeighbours(w.x+1,w.y-1).contains(w)) {
          symmetricNeighbours.add(Index2d(w.x+1,w.y-1));
        }
        if (w.x > 0 && w.y < image.height-1 && getNeighbours(w.x-1,w.y+1).contains(w)) {
          symmetricNeighbours.add(Index2d(w.x-1,w.y+1));
        }
        if (w.y < image.height-1 && getNeighbours(w.x,w.y+1).contains(w)) {
          symmetricNeighbours.add(Index2d(w.x,w.y+1));
        }
        if (w.x < image.width-1 && w.y < image.height-1 && getNeighbours(w.x+1,w.y+1).contains(w)) {
          symmetricNeighbours.add(Index2d(w.x+1,w.y+1));
        }
        if (w.x > 0 && getNeighbours(w.x-1,w.y).contains(w)) {
          symmetricNeighbours.add(Index2d(w.x-1,w.y));
        }
        if (w.x <image.width-1 && getNeighbours(w.x+1,w.y).contains(w)) {
          symmetricNeighbours.add(Index2d(w.x+1,w.y));
        }
        symmetricNeighbours.forEach((neighbour) {
          //if edge is foreground edge and not yet labbeled
          if (isWeak(neighbour.x,neighbour.x) && labeledPixels.getPixel(neighbour.x, neighbour.y) == 0) {
            currentBlobNeighbours.add(neighbour);
          }
        });
      }
      if (isStrongEdge) {
        edges.add(currentEdge);
      } else {
        nonEdges.addAll(currentEdge);
      }
      currentLabel++;
    }
  }

  nonEdges.forEach((w) {
    image.setPixelRgba(w.x, w.y, 0,0,0);
  });

  if (onImageResult != null) onImageResult(image);

  return edges;
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
  return threshold;
}