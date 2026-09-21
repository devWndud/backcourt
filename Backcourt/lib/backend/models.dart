import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? dateTimeFromFirestore(Object? value) => switch (value) {
  Timestamp value => value.toDate(),
  DateTime value => value,
  _ => null,
};

class CourtSummary {
  const CourtSummary({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
    this.facts = const [],
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;
  final List<String> facts;

  Map<String, Object?> toFirestore() => {
    'name': name,
    'location': GeoPoint(latitude, longitude),
    'address': address,
    'facts': facts,
    'source': id.startsWith('sample-') ? 'backcourt' : 'openstreetmap',
    'status': 'active',
  };
}

CourtSummary? courtSummaryFromProfileData(Object? value) {
  if (value is! Map) return null;
  final id = value['id'];
  final name = value['name'];
  final location = value['location'];
  if (id is! String || name is! String || location is! GeoPoint) return null;
  final rawFacts = value['facts'];
  return CourtSummary(
    id: id,
    name: name,
    latitude: location.latitude,
    longitude: location.longitude,
    address: value['address'] as String?,
    facts: rawFacts is List
        ? rawFacts.whereType<String>().toList(growable: false)
        : const [],
  );
}

class AppUserProfile {
  const AppUserProfile({
    required this.uid,
    required this.displayName,
    this.email,
    this.username,
    this.bio = '',
    this.photoUrl,
    this.birthYear,
    this.guardianConsentAt,
    this.checkinCount = 0,
    this.postCount = 0,
    this.meetupCount = 0,
    this.liveCourtCount = 0,
    this.role = 'user',
    this.onboardingComplete = true,
    this.homeCourt,
    this.homeCourts = const [],
    this.lastActiveCourt,
    this.position,
    this.playStyles = const [],
  });

  factory AppUserProfile.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final legacyHomeCourt = courtSummaryFromProfileData(data['homeCourt']);
    final savedHomeCourts =
        (data['homeCourts'] as List?)
            ?.map(courtSummaryFromProfileData)
            .whereType<CourtSummary>()
            .toList(growable: false) ??
        const <CourtSummary>[];
    final homeCourts = savedHomeCourts.isNotEmpty
        ? savedHomeCourts
        : legacyHomeCourt == null
        ? const <CourtSummary>[]
        : <CourtSummary>[legacyHomeCourt];
    return AppUserProfile(
      uid: doc.id,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? data['displayName'] as String
          : '새로운 플레이어',
      email: data['email'] as String?,
      username: (data['username'] as String?)?.trim(),
      bio: (data['bio'] as String?)?.trim() ?? '',
      photoUrl: data['photoUrl'] as String?,
      birthYear: (data['birthYear'] as num?)?.toInt(),
      guardianConsentAt: dateTimeFromFirestore(data['guardianConsentAt']),
      checkinCount: (data['checkinCount'] as num?)?.toInt() ?? 0,
      postCount: (data['postCount'] as num?)?.toInt() ?? 0,
      meetupCount: (data['meetupCount'] as num?)?.toInt() ?? 0,
      liveCourtCount: (data['liveCourtCount'] as num?)?.toInt() ?? 0,
      role: data['role'] as String? ?? 'user',
      onboardingComplete:
          data['onboardingComplete'] as bool? ?? data['birthYear'] != null,
      homeCourt:
          legacyHomeCourt ?? (homeCourts.isEmpty ? null : homeCourts.first),
      homeCourts: homeCourts,
      lastActiveCourt: courtSummaryFromProfileData(data['lastActiveCourt']),
      position: data['position'] as String?,
      playStyles:
          (data['playStyles'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
    );
  }

  final String uid;
  final String displayName;
  final String? email;
  final String? username;
  final String bio;
  final String? photoUrl;
  final int? birthYear;
  final DateTime? guardianConsentAt;
  final int checkinCount;
  final int postCount;
  final int meetupCount;
  final int liveCourtCount;
  final String role;
  final bool onboardingComplete;
  final CourtSummary? homeCourt;
  final List<CourtSummary> homeCourts;
  final CourtSummary? lastActiveCourt;
  final String? position;
  final List<String> playStyles;

  bool get isComplete => birthYear != null;
  CourtSummary? get preferredCourt =>
      lastActiveCourt ??
      homeCourt ??
      (homeCourts.isEmpty ? null : homeCourts.first);
  bool get isOperator => role == 'admin' || role == 'operator';
  bool get isMinor =>
      birthYear != null && DateTime.now().year - birthYear! < 19;
}

enum CourtReportType {
  name('name'),
  duplicate('duplicate'),
  closed('closed');

  const CourtReportType(this.value);

  final String value;

  static CourtReportType fromValue(Object? value) => switch (value) {
    'duplicate' => duplicate,
    'closed' => closed,
    _ => name,
  };
}

enum CourtReportStatus {
  pending('pending'),
  onHold('on_hold'),
  approved('approved'),
  rejected('rejected');

  const CourtReportStatus(this.value);

  final String value;

  static CourtReportStatus fromValue(Object? value) => switch (value) {
    'on_hold' => onHold,
    'approved' => approved,
    'rejected' => rejected,
    _ => pending,
  };
}

class CourtReport {
  const CourtReport({
    required this.id,
    required this.courtId,
    required this.currentName,
    required this.reason,
    required this.uid,
    required this.requesterName,
    required this.type,
    required this.status,
    required this.createdAt,
    this.requestedName,
    this.latitude,
    this.longitude,
    this.reviewedAt,
    this.reviewedBy,
    this.resolutionNote,
  });

  factory CourtReport.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final location = data['location'];
    return CourtReport(
      id: doc.id,
      courtId: data['courtId'] as String? ?? '',
      currentName: data['currentName'] as String? ?? '농구 코트',
      requestedName: data['requestedName'] as String?,
      reason: data['reason'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
      requesterName: data['requesterName'] as String? ?? '플레이어',
      type: CourtReportType.fromValue(data['reportType']),
      status: CourtReportStatus.fromValue(data['status']),
      createdAt: dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
      latitude: location is GeoPoint ? location.latitude : null,
      longitude: location is GeoPoint ? location.longitude : null,
      reviewedAt: dateTimeFromFirestore(data['reviewedAt']),
      reviewedBy: data['reviewedBy'] as String?,
      resolutionNote: data['resolutionNote'] as String?,
    );
  }

  final String id;
  final String courtId;
  final String currentName;
  final String? requestedName;
  final String reason;
  final String uid;
  final String requesterName;
  final CourtReportType type;
  final CourtReportStatus status;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? resolutionNote;
}

class MediaItem {
  const MediaItem({
    required this.url,
    required this.type,
    required this.storagePath,
  });

  factory MediaItem.fromMap(Map<String, dynamic> map) => MediaItem(
    url: map['url'] as String? ?? '',
    type: map['type'] as String? ?? 'image',
    storagePath: map['storagePath'] as String? ?? '',
  );

  final String url;
  final String type;
  final String storagePath;

  Map<String, Object?> toMap() => {
    'url': url,
    'type': type,
    'storagePath': storagePath,
  };
}

class CheckinRecord {
  const CheckinRecord({
    required this.id,
    required this.uid,
    required this.courtId,
    required this.courtName,
    required this.displayName,
    required this.checkedInAt,
    required this.distanceMeters,
  });

  factory CheckinRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return CheckinRecord(
      id: doc.id,
      uid: data['uid'] as String,
      courtId: data['courtId'] as String,
      courtName: data['courtName'] as String? ?? '농구 코트',
      displayName: data['displayName'] as String? ?? '플레이어',
      checkedInAt: dateTimeFromFirestore(data['checkedInAt']) ?? DateTime.now(),
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String uid;
  final String courtId;
  final String courtName;
  final String displayName;
  final DateTime checkedInAt;
  final double distanceMeters;
}

class RankingEntry {
  const RankingEntry({
    required this.uid,
    required this.displayName,
    required this.count,
  });

  final String uid;
  final String displayName;
  final int count;
}

class ActivePlaySession {
  const ActivePlaySession({
    required this.uid,
    required this.displayName,
    required this.courtId,
    required this.courtName,
    required this.startedAt,
    required this.monthKey,
  });

  factory ActivePlaySession.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ActivePlaySession(
      uid: data['uid'] as String,
      displayName: data['displayName'] as String? ?? '플레이어',
      courtId: data['courtId'] as String,
      courtName: data['courtName'] as String? ?? '농구 코트',
      startedAt: dateTimeFromFirestore(data['startedAt']) ?? DateTime.now(),
      monthKey: data['monthKey'] as String? ?? '',
    );
  }

  final String uid;
  final String displayName;
  final String courtId;
  final String courtName;
  final DateTime startedAt;
  final String monthKey;
}

enum CourtRankingPeriod { all, month, week }

class MonthlyPlayStat {
  const MonthlyPlayStat({
    required this.uid,
    required this.displayName,
    required this.monthKey,
    required this.totalMinutes,
    required this.sessionCount,
    this.courtId = '',
    this.courtName = '',
    this.username,
    this.photoUrl,
  });

  factory MonthlyPlayStat.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MonthlyPlayStat(
      uid: data['uid'] as String,
      displayName: data['displayName'] as String? ?? '플레이어',
      monthKey: data['monthKey'] as String? ?? '',
      totalMinutes: (data['totalMinutes'] as num?)?.toInt() ?? 0,
      sessionCount: (data['sessionCount'] as num?)?.toInt() ?? 0,
      courtId: data['courtId'] as String? ?? '',
      courtName: data['courtName'] as String? ?? '',
      username: data['username'] as String?,
      photoUrl: data['photoUrl'] as String?,
    );
  }

  final String uid;
  final String displayName;
  final String monthKey;
  final int totalMinutes;
  final int sessionCount;
  final String courtId;
  final String courtName;
  final String? username;
  final String? photoUrl;
}

class ReviewRecord {
  const ReviewRecord({
    required this.id,
    required this.uid,
    required this.authorName,
    required this.courtId,
    required this.rating,
    required this.text,
    required this.createdAt,
    required this.editableUntil,
    required this.media,
    required this.courtCondition,
    required this.lighting,
    required this.netCondition,
    required this.crowdLevel,
  });

  factory ReviewRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ReviewRecord(
      id: doc.id,
      uid: data['uid'] as String,
      authorName: data['authorName'] as String? ?? '플레이어',
      courtId: data['courtId'] as String,
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      text: data['text'] as String? ?? '',
      createdAt: dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
      editableUntil:
          dateTimeFromFirestore(data['editableUntil']) ?? DateTime.now(),
      media: [
        for (final item in (data['media'] as List<dynamic>? ?? const []))
          MediaItem.fromMap(Map<String, dynamic>.from(item as Map)),
      ],
      courtCondition: data['courtCondition'] as String? ?? '보통',
      lighting: data['lighting'] as String? ?? '모름',
      netCondition: data['netCondition'] as String? ?? '모름',
      crowdLevel: data['crowdLevel'] as String? ?? '보통',
    );
  }

  final String id;
  final String uid;
  final String authorName;
  final String courtId;
  final double rating;
  final String text;
  final DateTime createdAt;
  final DateTime editableUntil;
  final List<MediaItem> media;
  final String courtCondition;
  final String lighting;
  final String netCondition;
  final String crowdLevel;
}

class MeetupRecord {
  const MeetupRecord({
    required this.id,
    required this.courtId,
    required this.courtName,
    required this.startsAt,
    required this.capacity,
    required this.gameType,
    required this.level,
    required this.participantUids,
    required this.createdBy,
  });

  factory MeetupRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MeetupRecord(
      id: doc.id,
      courtId: data['courtId'] as String,
      courtName: data['courtName'] as String? ?? '농구 코트',
      startsAt: dateTimeFromFirestore(data['startsAt']) ?? DateTime.now(),
      capacity: (data['capacity'] as num?)?.toInt() ?? 2,
      gameType: data['gameType'] as String? ?? '3 vs 3',
      level: data['level'] as String? ?? '누구나',
      participantUids: List<String>.from(
        data['participantUids'] as List<dynamic>? ?? const [],
      ),
      createdBy: data['createdBy'] as String? ?? '',
    );
  }

  final String id;
  final String courtId;
  final String courtName;
  final DateTime startsAt;
  final int capacity;
  final String gameType;
  final String level;
  final List<String> participantUids;
  final String createdBy;

  bool get isFull => participantUids.length >= capacity;
}

class FavoriteCourtRecord {
  const FavoriteCourtRecord({
    required this.id,
    required this.uid,
    required this.court,
    required this.createdAt,
  });

  factory FavoriteCourtRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final location = data['location'];
    return FavoriteCourtRecord(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      court: CourtSummary(
        id: data['courtId'] as String? ?? '',
        name: data['courtName'] as String? ?? '농구 코트',
        latitude: location is GeoPoint ? location.latitude : 0,
        longitude: location is GeoPoint ? location.longitude : 0,
        address: data['address'] as String?,
      ),
      createdAt: dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
    );
  }

  final String id;
  final String uid;
  final CourtSummary court;
  final DateTime createdAt;
}

enum AppNotificationType {
  live('live'),
  meetup('meetup'),
  meetupJoin('meetup_join'),
  meetupCancelled('meetup_cancelled'),
  comment('comment'),
  courtReport('court_report');

  const AppNotificationType(this.value);

  final String value;

  static AppNotificationType fromValue(Object? value) => switch (value) {
    'meetup' => meetup,
    'meetup_join' => meetupJoin,
    'meetup_cancelled' => meetupCancelled,
    'comment' => comment,
    'court_report' => courtReport,
    _ => live,
  };
}

class AppNotificationRecord {
  const AppNotificationRecord({
    required this.id,
    required this.targetUid,
    required this.actorUid,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.courtId,
    this.entityId,
    this.readAt,
  });

  factory AppNotificationRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return AppNotificationRecord(
      id: doc.id,
      targetUid: data['targetUid'] as String? ?? '',
      actorUid: data['actorUid'] as String? ?? '',
      type: AppNotificationType.fromValue(data['type']),
      title: data['title'] as String? ?? '빽코트',
      body: data['body'] as String? ?? '',
      courtId: data['courtId'] as String?,
      entityId: data['entityId'] as String?,
      createdAt: dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
      readAt: dateTimeFromFirestore(data['readAt']),
    );
  }

  final String id;
  final String targetUid;
  final String actorUid;
  final AppNotificationType type;
  final String title;
  final String body;
  final String? courtId;
  final String? entityId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;
}

class CommentRecord {
  const CommentRecord({
    required this.id,
    required this.postId,
    required this.uid,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.authorPhotoUrl,
  });

  factory CommentRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return CommentRecord(
      id: doc.id,
      postId: data['postId'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '플레이어',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      text: data['text'] as String? ?? '',
      createdAt: dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
    );
  }

  final String id;
  final String postId;
  final String uid;
  final String authorName;
  final String? authorPhotoUrl;
  final String text;
  final DateTime createdAt;
}

class BlockedUserRecord {
  const BlockedUserRecord({
    required this.id,
    required this.blockedUid,
    required this.displayName,
    required this.createdAt,
  });

  factory BlockedUserRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return BlockedUserRecord(
      id: doc.id,
      blockedUid: data['blockedUid'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '차단한 사용자',
      createdAt: dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
    );
  }

  final String id;
  final String blockedUid;
  final String displayName;
  final DateTime createdAt;
}

enum LiveCourtActivity {
  shooting('shooting', '슛 연습'),
  playing('playing', '게임 중'),
  looking('looking', '인원 모집'),
  full('full', '만석'),
  wet('wet', '바닥 젖음');

  const LiveCourtActivity(this.value, this.label);

  final String value;
  final String label;

  static LiveCourtActivity fromValue(Object? value) => switch (value) {
    'playing' => playing,
    'looking' => looking,
    'full' => full,
    'wet' => wet,
    _ => shooting,
  };
}

class LiveCourtStatus {
  const LiveCourtStatus({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.courtId,
    required this.courtName,
    required this.latitude,
    required this.longitude,
    required this.activity,
    required this.playerCount,
    required this.neededPlayers,
    required this.distanceMeters,
    required this.arrivalUids,
    required this.startedAt,
    required this.updatedAt,
    required this.expiresAt,
    this.username,
    this.photoUrl,
  });

  factory LiveCourtStatus.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final location = data['location'];
    final username = (data['username'] as String?)?.trim();
    final photoUrl = (data['photoUrl'] as String?)?.trim();
    return LiveCourtStatus(
      id: doc.id,
      uid: data['uid'] as String? ?? doc.id,
      displayName: data['displayName'] as String? ?? '플레이어',
      username: username?.isEmpty == true ? null : username,
      photoUrl: photoUrl?.isEmpty == true ? null : photoUrl,
      courtId: data['courtId'] as String? ?? '',
      courtName: data['courtName'] as String? ?? '농구 코트',
      latitude: location is GeoPoint ? location.latitude : 0,
      longitude: location is GeoPoint ? location.longitude : 0,
      activity: LiveCourtActivity.fromValue(data['activity']),
      playerCount: (data['playerCount'] as num?)?.toInt() ?? 1,
      neededPlayers: (data['neededPlayers'] as num?)?.toInt() ?? 0,
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0,
      arrivalUids: List<String>.from(
        data['arrivalUids'] as List<dynamic>? ?? const [],
      ),
      startedAt: dateTimeFromFirestore(data['startedAt']) ?? DateTime.now(),
      updatedAt: dateTimeFromFirestore(data['updatedAt']) ?? DateTime.now(),
      expiresAt: dateTimeFromFirestore(data['expiresAt']) ?? DateTime.now(),
    );
  }

  final String id;
  final String uid;
  final String displayName;
  final String? username;
  final String? photoUrl;
  final String courtId;
  final String courtName;
  final double latitude;
  final double longitude;
  final LiveCourtActivity activity;
  final int playerCount;
  final int neededPlayers;
  final double distanceMeters;
  final List<String> arrivalUids;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime expiresAt;

  bool get isActive => expiresAt.isAfter(DateTime.now());
  bool get isLooking => activity == LiveCourtActivity.looking;
}

class PostRecord {
  const PostRecord({
    required this.id,
    required this.uid,
    required this.authorName,
    required this.courtId,
    required this.courtName,
    required this.text,
    required this.media,
    required this.likeUids,
    required this.createdAt,
    this.authorUsername,
    this.authorPhotoUrl,
    this.commentCount = 0,
    this.latitude,
    this.longitude,
  });

  factory PostRecord.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final location = data['location'];
    return PostRecord(
      id: doc.id,
      uid: data['uid'] as String,
      authorName: data['authorName'] as String? ?? '플레이어',
      authorUsername: data['authorUsername'] as String?,
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      courtId: data['courtId'] as String? ?? '',
      courtName: data['courtName'] as String? ?? '오늘의 코트',
      text: data['text'] as String? ?? '',
      media: [
        for (final item in (data['media'] as List<dynamic>? ?? const []))
          MediaItem.fromMap(Map<String, dynamic>.from(item as Map)),
      ],
      likeUids: List<String>.from(
        data['likeUids'] as List<dynamic>? ?? const [],
      ),
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      latitude: location is GeoPoint ? location.latitude : null,
      longitude: location is GeoPoint ? location.longitude : null,
      createdAt: dateTimeFromFirestore(data['createdAt']) ?? DateTime.now(),
    );
  }

  final String id;
  final String uid;
  final String authorName;
  final String? authorUsername;
  final String? authorPhotoUrl;
  final String courtId;
  final String courtName;
  final String text;
  final List<MediaItem> media;
  final List<String> likeUids;
  final int commentCount;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
}

class BackcourtException implements Exception {
  const BackcourtException(this.message);

  final String message;

  @override
  String toString() => message;
}
