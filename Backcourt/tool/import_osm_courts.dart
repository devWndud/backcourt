import 'dart:convert';
import 'dart:io';

const _overpassUrl = 'https://overpass-api.de/api/interpreter';
const _outputPath = 'assets/data/korea_basketball_courts.geojson';
const _query = r'''
[out:json][timeout:180];
area["ISO3166-1"="KR"][admin_level=2]->.kr;
nwr["sport"~"(^|;)basketball(;|$)"](area.kr);
out center tags;
''';

Future<void> main() async {
  final client = HttpClient();
  client.userAgent = 'Backcourt court importer (https://backcourt.kr)';

  try {
    final request = await client.postUrl(Uri.parse(_overpassUrl));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write('data=${Uri.encodeQueryComponent(_query)}');

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Overpass API returned ${response.statusCode}: $body',
        uri: Uri.parse(_overpassUrl),
      );
    }

    final payload = jsonDecode(body) as Map<String, dynamic>;
    final elements = payload['elements'] as List<dynamic>;
    final features = <Map<String, dynamic>>[];
    var unnamedCount = 0;

    for (final rawElement in elements) {
      final element = rawElement as Map<String, dynamic>;
      final type = element['type'] as String;
      final osmId = element['id'] as num;
      final tags = (element['tags'] as Map<String, dynamic>?) ?? const {};
      final center = element['center'] as Map<String, dynamic>?;
      final latitude = (element['lat'] ?? center?['lat']) as num?;
      final longitude = (element['lon'] ?? center?['lon']) as num?;
      if (latitude == null || longitude == null) continue;

      final sourceName = _firstText(tags, ['name:ko', 'name']);
      if (sourceName == null) unnamedCount++;
      final featureIndex = features.length + 1;
      final access = _firstText(tags, ['access']);
      final surface = _firstText(tags, ['surface']);
      final lit = _firstText(tags, ['lit']);
      final hoops = _firstText(tags, ['hoops']);
      final indoor = _firstText(tags, ['indoor']);
      final covered = _firstText(tags, ['covered']);
      final fee = _firstText(tags, ['fee']);
      final openingHours = _firstText(tags, ['opening_hours']);
      final operator = _firstText(tags, ['operator']);
      final address = _address(tags);
      final name = sourceName ?? _fallbackName(tags, address);
      final stableId = 'osm_${type}_${osmId.toInt()}';

      features.add({
        'type': 'Feature',
        'id': stableId,
        'geometry': {
          'type': 'Point',
          'coordinates': [longitude.toDouble(), latitude.toDouble()],
        },
        'properties': {
          'feature_index': featureIndex,
          'name': name,
          'name_source': sourceName == null ? 'generated' : 'openstreetmap',
          'osm_type': type,
          'osm_id': osmId.toInt(),
          'source': 'OpenStreetMap',
          'source_url': 'https://www.openstreetmap.org/$type/${osmId.toInt()}',
          'verified': false,
          'access': ?access,
          'surface': ?surface,
          'lit': ?lit,
          'hoops': ?hoops,
          'indoor': ?indoor,
          'covered': ?covered,
          'fee': ?fee,
          'opening_hours': ?openingHours,
          'operator': ?operator,
          'address': ?address,
        },
      });
    }

    final geoJson = {
      'type': 'FeatureCollection',
      'metadata': {
        'source': 'OpenStreetMap',
        'license': 'ODbL 1.0',
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'osm_base_timestamp':
            (payload['osm3s'] as Map<String, dynamic>?)?['timestamp_osm_base'],
        'query': 'South Korea sport=basketball, including multi-sport courts',
      },
      'features': features,
    };

    final output = File(_outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsString(jsonEncode(geoJson));
    stdout.writeln(
      'Saved ${features.length} courts to $_outputPath '
      '($unnamedCount without a name).',
    );
  } finally {
    client.close(force: true);
  }
}

String _fallbackName(Map<String, dynamic> tags, String? address) {
  for (final key in [
    'addr:place',
    'addr:subdistrict',
    'addr:district',
    'addr:city',
  ]) {
    final area = _firstText(tags, [key]);
    if (area != null) return '$area 농구장';
  }
  if (address != null) {
    for (final part in address.split(RegExp(r'\s+')).reversed) {
      if (RegExp(r'(동|읍|면|리|구|시|군)$').hasMatch(part)) {
        return '$part 농구장';
      }
    }
  }
  return '지역 농구장';
}

String? _firstText(Map<String, dynamic> tags, List<String> keys) {
  for (final key in keys) {
    final value = tags[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String? _address(Map<String, dynamic> tags) {
  final full = _firstText(tags, ['addr:full']);
  if (full != null) return full;

  final parts = [
    _firstText(tags, ['addr:province']),
    _firstText(tags, ['addr:city']),
    _firstText(tags, ['addr:district']),
    _firstText(tags, ['addr:street']),
    _firstText(tags, ['addr:housenumber']),
  ].whereType<String>().toList();
  return parts.isEmpty ? null : parts.join(' ');
}
