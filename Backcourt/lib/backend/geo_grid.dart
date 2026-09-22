import 'dart:math' as math;

class GeoGrid {
  const GeoGrid._();

  static const double cellSize = .05;

  static String cellFor(double latitude, double longitude) {
    final lat = (latitude / cellSize).floor();
    final lon = (longitude / cellSize).floor();
    return '${lat}_$lon';
  }

  static List<String> nearbyCells(
    double latitude,
    double longitude, {
    double radiusKm = 5,
  }) {
    final centerLat = (latitude / cellSize).floor();
    final centerLon = (longitude / cellSize).floor();
    final latCells = (radiusKm / 111 / cellSize).ceil();
    final longitudeKm = 111 * math.cos(latitude * math.pi / 180).abs();
    final lonCells = (radiusKm / longitudeKm / cellSize).ceil();
    return [
      for (var lat = centerLat - latCells; lat <= centerLat + latCells; lat++)
        for (var lon = centerLon - lonCells; lon <= centerLon + lonCells; lon++)
          '${lat}_$lon',
    ];
  }
}
