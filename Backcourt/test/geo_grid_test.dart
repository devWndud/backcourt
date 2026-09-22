import 'package:backcourt/backend/geo_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('주변 5km 쿼리 셀에 현재 위치가 포함된다', () {
    const latitude = 36.8151;
    const longitude = 127.1139;
    final cells = GeoGrid.nearbyCells(latitude, longitude);

    expect(cells, contains(GeoGrid.cellFor(latitude, longitude)));
    expect(cells.length, lessThanOrEqualTo(30));
    expect(cells.toSet().length, cells.length);
  });
}
