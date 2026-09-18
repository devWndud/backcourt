enum AppReleaseAction { open, optionalUpdate, requiredUpdate, maintenance }

class AppReleaseDecision {
  const AppReleaseDecision({
    required this.action,
    required this.message,
    required this.storeUrl,
    required this.targetVersion,
    this.maintenanceEndsAt,
  });

  final AppReleaseAction action;
  final String message;
  final String storeUrl;
  final String targetVersion;
  final DateTime? maintenanceEndsAt;
}

class AppReleaseConfig {
  const AppReleaseConfig({
    this.maintenanceEnabled = false,
    this.maintenanceMessage = '조금 뒤에 다시 접속해주세요.',
    this.maintenanceEndsAt,
    this.minIosVersion = '',
    this.latestIosVersion = '',
    this.iosStoreUrl = '',
    this.minAndroidVersion = '',
    this.latestAndroidVersion = '',
    this.androidStoreUrl = '',
    this.updateMessage = '최신 버전으로 업데이트해주세요.',
  });

  factory AppReleaseConfig.fromMap(Map<String, dynamic> map) {
    return AppReleaseConfig(
      maintenanceEnabled: map['maintenanceEnabled'] == true,
      maintenanceMessage: _text(map['maintenanceMessage'], '조금 뒤에 다시 접속해주세요.'),
      maintenanceEndsAt: _date(map['maintenanceEndsAt']),
      minIosVersion: _text(map['minIosVersion']),
      latestIosVersion: _text(map['latestIosVersion']),
      iosStoreUrl: _text(map['iosStoreUrl']),
      minAndroidVersion: _text(map['minAndroidVersion']),
      latestAndroidVersion: _text(map['latestAndroidVersion']),
      androidStoreUrl: _text(map['androidStoreUrl']),
      updateMessage: _text(map['updateMessage'], '최신 버전으로 업데이트해주세요.'),
    );
  }

  final bool maintenanceEnabled;
  final String maintenanceMessage;
  final DateTime? maintenanceEndsAt;
  final String minIosVersion;
  final String latestIosVersion;
  final String iosStoreUrl;
  final String minAndroidVersion;
  final String latestAndroidVersion;
  final String androidStoreUrl;
  final String updateMessage;

  AppReleaseDecision decide({
    required bool isIos,
    required String currentVersion,
  }) {
    final minimum = isIos ? minIosVersion : minAndroidVersion;
    final latest = isIos ? latestIosVersion : latestAndroidVersion;
    final storeUrl = isIos ? iosStoreUrl : androidStoreUrl;

    if (maintenanceEnabled) {
      return AppReleaseDecision(
        action: AppReleaseAction.maintenance,
        message: maintenanceMessage,
        storeUrl: storeUrl,
        targetVersion: latest,
        maintenanceEndsAt: maintenanceEndsAt,
      );
    }
    if (isVersionLower(currentVersion, minimum)) {
      return AppReleaseDecision(
        action: AppReleaseAction.requiredUpdate,
        message: updateMessage,
        storeUrl: storeUrl,
        targetVersion: minimum,
      );
    }
    if (isVersionLower(currentVersion, latest)) {
      return AppReleaseDecision(
        action: AppReleaseAction.optionalUpdate,
        message: updateMessage,
        storeUrl: storeUrl,
        targetVersion: latest,
      );
    }
    return const AppReleaseDecision(
      action: AppReleaseAction.open,
      message: '',
      storeUrl: '',
      targetVersion: '',
    );
  }
}

bool isVersionLower(String current, String target) {
  if (target.trim().isEmpty) return false;
  final currentParts = _versionParts(current);
  final targetParts = _versionParts(target);
  final length = currentParts.length > targetParts.length
      ? currentParts.length
      : targetParts.length;
  for (var index = 0; index < length; index++) {
    final currentPart = index < currentParts.length ? currentParts[index] : 0;
    final targetPart = index < targetParts.length ? targetParts[index] : 0;
    if (currentPart != targetPart) return currentPart < targetPart;
  }
  return false;
}

List<int> _versionParts(String value) {
  final core = value.trim().split(RegExp(r'[-+]')).first;
  return core.split('.').map((part) {
    final digits = RegExp(r'^\d+').firstMatch(part)?.group(0);
    return int.tryParse(digits ?? '') ?? 0;
  }).toList();
}

String _text(Object? value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  try {
    final date = (value as dynamic).toDate();
    return date is DateTime ? date : null;
  } catch (_) {
    return null;
  }
}
