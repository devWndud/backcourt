import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OSM 전국 농구 코트 시드 데이터가 유효하다', () async {
    final file = File('assets/data/korea_basketball_courts.geojson');
    final geoJson =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final metadata = geoJson['metadata'] as Map<String, dynamic>;
    final features = geoJson['features'] as List<dynamic>;

    expect(geoJson['type'], 'FeatureCollection');
    expect(metadata['source'], 'OpenStreetMap');
    expect(metadata['license'], 'ODbL 1.0');
    expect(features.length, greaterThanOrEqualTo(3000));

    final ids = <Object?>{};
    final stableIds = <String>{};
    for (final rawFeature in features) {
      final feature = rawFeature as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List<dynamic>;
      final properties = feature['properties'] as Map<String, dynamic>;

      expect(ids.add(feature['id']), isTrue);
      final osmType = properties['osm_type'] as String;
      final osmId = (properties['osm_id'] as num).toInt();
      expect(stableIds.add('osm_${osmType}_$osmId'), isTrue);
      expect(geometry['type'], 'Point');
      expect(coordinates, hasLength(2));
      expect((coordinates[0] as num).toDouble(), inInclusiveRange(124, 132));
      expect((coordinates[1] as num).toDouble(), inInclusiveRange(33, 39));
      expect(properties['source'], 'OpenStreetMap');
      expect(properties['name'], isNot('이름 없는 농구 코트'));
      expect((properties['name'] as String).contains('#'), isFalse);
      expect(properties['administrative_name'], isA<String>());
      expect(
        properties['source_url'],
        startsWith('https://www.openstreetmap.org/'),
      );
    }
  });
}
