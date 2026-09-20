import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import 'cloudinary_media_store.dart';
import 'models.dart';

class BackcourtRepository {
  BackcourtRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    CloudinaryMediaStore? mediaStore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _mediaStore = mediaStore ?? CloudinaryMediaStore();

  static const reviewWindow = Duration(hours: 48);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final CloudinaryMediaStore _mediaStore;

  User get currentUser {
    final user = _auth.currentUser;
    if (user == null) throw const BackcourtException('로그인이 필요해요.');
    return user;
  }

  String get currentUid => currentUser.uid;

  DocumentReference<Map<String, dynamic>> get _currentUserRef =>
      _firestore.collection('users').doc(currentUid);

  void _requireSavedCourt(CourtSummary court) {
    if (court.id.startsWith('sample-')) {
      throw const BackcourtException('코트 탭에서 실제 코트를 먼저 선택해주세요.');
    }
  }

  Future<void> ensureUserProfile(User user) async {
    final ref = _firestore.collection('users').doc(user.uid);
    final privateRef = _firestore.collection('private_users').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        transaction.set(ref, {
          'displayName': _defaultDisplayName(user),
          'photoUrl': user.photoURL,
          'role': 'user',
          'checkinCount': 0,
          'postCount': 0,
          'meetupCount': 0,
          'liveCourtCount': 0,
          'onboardingComplete': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final data = snapshot.data()!;
        final hasCustomPhoto =
            (data['photoStoragePath'] as String?)?.isNotEmpty == true;
        final savedName = (data['displayName'] as String?)?.trim() ?? '';
        transaction.set(ref, {
          if (data.containsKey('email')) 'email': FieldValue.delete(),
          if (savedName.length < 2 || savedName.length > 24)
            'displayName': _defaultDisplayName(user),
          if (!hasCustomPhoto) 'photoUrl': user.photoURL,
          if (!data.containsKey('onboardingComplete') &&
              data['birthYear'] != null)
            'onboardingComplete': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      transaction.set(privateRef, {
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  String _defaultDisplayName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.length >= 2) {
      return displayName.length <= 24
          ? displayName
          : displayName.substring(0, 24);
    }
    final emailName = user.email?.split('@').first.trim();
    if (emailName != null && emailName.length >= 2) {
      return emailName.length <= 24 ? emailName : emailName.substring(0, 24);
    }
    return '새로운 플레이어';
  }

  Stream<AppUserProfile?> watchCurrentProfile() =>
      _currentUserRef.snapshots().map(
        (snapshot) =>
            snapshot.exists ? AppUserProfile.fromDocument(snapshot) : null,
      );

  Future<AppUserProfile> getCurrentProfile() async {
    final snapshot = await _currentUserRef.get();
    if (!snapshot.exists) {
      await ensureUserProfile(currentUser);
      return AppUserProfile.fromDocument(await _currentUserRef.get());
    }
    return AppUserProfile.fromDocument(snapshot);
  }

  Future<void> completeProfile({
    required String displayName,
    required int birthYear,
    required bool guardianConsent,
  }) async {
    final cleanName = displayName.trim();
    if (cleanName.length < 2 || cleanName.length > 24) {
      throw const BackcourtException('이름은 2~24자로 입력해주세요.');
    }
    final age = DateTime.now().year - birthYear;
    if (birthYear < 1900 || age < 0 || age > 120) {
      throw const BackcourtException('출생 연도를 확인해주세요.');
    }
    if (age < 19 && !guardianConsent) {
      throw const BackcourtException('미성년자는 보호자 동의가 필요해요.');
    }
    await _currentUserRef.set({
      'displayName': cleanName,
      'birthYear': birthYear,
      'guardianConsentAt': age < 19 ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> completePlayerSetup({
    required CourtSummary homeCourt,
    required String position,
    required List<String> playStyles,
  }) async {
    _requireSavedCourt(homeCourt);
    const allowedPositions = {'guard', 'forward', 'center'};
    const allowedStyles = {
      'shooting',
      'drive',
      'passing',
      'defense',
      'rebound',
    };
    final cleanStyles = playStyles.toSet().toList(growable: false);
    if (!allowedPositions.contains(position)) {
      throw const BackcourtException('포지션을 선택해주세요.');
    }
    if (cleanStyles.isEmpty ||
        cleanStyles.length > 3 ||
        cleanStyles.any((style) => !allowedStyles.contains(style))) {
      throw const BackcourtException('플레이 스타일을 1~3개 선택해주세요.');
    }
    await _currentUserRef.set({
      'homeCourt': {
        'id': homeCourt.id,
        'name': homeCourt.name,
        'location': GeoPoint(homeCourt.latitude, homeCourt.longitude),
        'address': homeCourt.address,
        'facts': homeCourt.facts,
      },
      'position': position,
      'playStyles': cleanStyles,
      'onboardingComplete': true,
      'onboardingCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String normalizeUsername(String value) => value.trim().toLowerCase();

  static bool isValidUsername(String value) => RegExp(
    r'^[a-z0-9][a-z0-9._]{1,18}[a-z0-9]$',
  ).hasMatch(normalizeUsername(value));

  Future<bool> isUsernameAvailable(String value) async {
    final username = normalizeUsername(value);
    if (!isValidUsername(username)) return false;
    final snapshot = await _firestore
        .collection('usernames')
        .doc(username)
        .get();
    return !snapshot.exists || snapshot.data()?['uid'] == currentUid;
  }

  Future<void> updateProfile({
    required String displayName,
    required String username,
    required String bio,
    XFile? profilePhoto,
  }) async {
    final cleanName = displayName.trim();
    final cleanUsername = normalizeUsername(username);
    final cleanBio = bio.trim();
    if (cleanName.length < 2 || cleanName.length > 24) {
      throw const BackcourtException('이름은 2~24자로 입력해주세요.');
    }
    if (!isValidUsername(cleanUsername)) {
      throw const BackcourtException('아이디는 영문 소문자·숫자·._ 조합 3~20자로 입력해주세요.');
    }
    if (cleanBio.length > 120) {
      throw const BackcourtException('소개는 120자까지 입력할 수 있어요.');
    }

    MediaItem? uploadedPhoto;
    if (profilePhoto != null) {
      try {
        uploadedPhoto = await _mediaStore.upload(
          file: profilePhoto,
          type: 'image',
          folder: 'users/$currentUid/profile',
        );
      } on CloudinaryMediaException catch (error) {
        throw BackcourtException(error.message);
      }
    }

    await _firestore.runTransaction((transaction) async {
      final userRef = _currentUserRef;
      final userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists) {
        throw const BackcourtException('사용자 정보를 찾지 못했어요.');
      }
      final userData = userSnapshot.data()!;
      final previousUsername = (userData['username'] as String?)
          ?.trim()
          .toLowerCase();
      final usernameRef = _firestore.collection('usernames').doc(cleanUsername);
      final usernameSnapshot = await transaction.get(usernameRef);
      DocumentSnapshot<Map<String, dynamic>>? previousUsernameSnapshot;
      if (previousUsername != null &&
          previousUsername.isNotEmpty &&
          previousUsername != cleanUsername) {
        previousUsernameSnapshot = await transaction.get(
          _firestore.collection('usernames').doc(previousUsername),
        );
      }
      if (usernameSnapshot.exists &&
          usernameSnapshot.data()?['uid'] != currentUid) {
        throw const BackcourtException('이미 사용 중인 아이디예요.');
      }

      if (previousUsernameSnapshot?.exists == true &&
          previousUsernameSnapshot?.data()?['uid'] == currentUid) {
        transaction.delete(previousUsernameSnapshot!.reference);
      }
      if (!usernameSnapshot.exists) {
        transaction.set(usernameRef, {
          'uid': currentUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      final updates = <String, dynamic>{
        'displayName': cleanName,
        'username': cleanUsername,
        'bio': cleanBio,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (uploadedPhoto != null) {
        updates['photoUrl'] = uploadedPhoto.url;
        updates['photoStoragePath'] = uploadedPhoto.storagePath;
      }
      transaction.update(userRef, updates);
    });

    try {
      await currentUser.updateDisplayName(cleanName);
    } catch (_) {}
    if (uploadedPhoto != null) {
      try {
        await currentUser.updatePhotoURL(uploadedPhoto.url);
      } catch (_) {}
    }
  }

  Stream<Map<String, String>> watchOperatorCourtNames() => _firestore
      .collection('courts')
      .where('nameSource', isEqualTo: 'operator')
      .snapshots()
      .map((snapshot) {
        final names = <String, String>{};
        for (final document in snapshot.docs) {
          final name = (document.data()['name'] as String?)?.trim();
          if (name != null && name.isNotEmpty) names[document.id] = name;
        }
        return names;
      });

  Stream<List<FavoriteCourtRecord>> watchFavoriteCourts() => _firestore
      .collection('favorite_courts')
      .where('uid', isEqualTo: currentUid)
      .snapshots()
      .map((snapshot) {
        final favorites = snapshot.docs
            .map(FavoriteCourtRecord.fromDocument)
            .toList();
        favorites.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return favorites;
      });

  Stream<bool> watchIsFavoriteCourt(String courtId) => _firestore
      .collection('favorite_courts')
      .doc('${currentUid}_$courtId')
      .snapshots()
      .map((snapshot) => snapshot.exists);

  Future<bool> toggleFavoriteCourt(CourtSummary court) async {
    _requireSavedCourt(court);
    final ref = _firestore
        .collection('favorite_courts')
        .doc('${currentUid}_${court.id}');
    final snapshot = await ref.get();
    if (snapshot.exists) {
      await ref.delete();
      return false;
    }
    await ref.set({
      'uid': currentUid,
      'courtId': court.id,
      'courtName': court.name,
      'location': GeoPoint(court.latitude, court.longitude),
      'address': court.address,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  Stream<List<AppNotificationRecord>> watchNotifications() => _firestore
      .collection('notifications')
      .where('targetUid', isEqualTo: currentUid)
      .orderBy('createdAt', descending: true)
      .limit(80)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(AppNotificationRecord.fromDocument)
            .toList(growable: false),
      );

  Stream<int> watchUnreadNotificationCount() => watchNotifications().map(
    (items) => items.where((item) => item.isUnread).length,
  );

  Future<void> markNotificationRead(String notificationId) => _firestore
      .collection('notifications')
      .doc(notificationId)
      .update({'readAt': FieldValue.serverTimestamp()});

  Future<void> markAllNotificationsRead() async {
    final snapshot = await _firestore
        .collection('notifications')
        .where('targetUid', isEqualTo: currentUid)
        .limit(400)
        .get();
    final unread = snapshot.docs.where((doc) => doc.data()['readAt'] == null);
    final batch = _firestore.batch();
    var hasUpdates = false;
    for (final doc in unread) {
      hasUpdates = true;
      batch.update(doc.reference, {'readAt': FieldValue.serverTimestamp()});
    }
    if (!hasUpdates) return;
    await batch.commit();
  }

  Map<String, Object?> _notificationEventData({
    required AppNotificationType type,
    required String title,
    required String body,
    String? courtId,
    String? entityId,
  }) => {
    'actorUid': currentUid,
    'type': type.value,
    'title': title,
    'body': body,
    'courtId': courtId,
    'entityId': entityId,
    'createdAt': FieldValue.serverTimestamp(),
    'status': 'pending',
  };

  Future<void> submitCourtNameRequest({
    required CourtSummary court,
    required String requestedName,
    required String reason,
  }) => submitCourtReport(
    court: court,
    type: CourtReportType.name,
    requestedName: requestedName,
    reason: reason,
  );

  Future<void> submitCourtReport({
    required CourtSummary court,
    required CourtReportType type,
    required String reason,
    String? requestedName,
  }) async {
    _requireSavedCourt(court);
    final cleanReason = reason.trim();
    final cleanName = requestedName?.trim();
    if (cleanReason.length < 2) {
      throw const BackcourtException('확인할 수 있는 근거를 적어주세요.');
    }
    if (type == CourtReportType.name &&
        (cleanName == null || cleanName.length < 2)) {
      throw const BackcourtException('새 코트명을 2자 이상 입력해주세요.');
    }
    final profile = await getCurrentProfile();
    await _firestore.collection('court_name_requests').add({
      'courtId': court.id,
      'currentName': court.name,
      'requestedName': type == CourtReportType.name ? cleanName : null,
      'reason': cleanReason,
      'reportType': type.value,
      'uid': currentUid,
      'requesterName': profile.displayName,
      'status': 'pending',
      'location': GeoPoint(court.latitude, court.longitude),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<CourtReport>> watchCourtReports() => _firestore
      .collection('court_name_requests')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(CourtReport.fromDocument).toList());

  Future<void> reviewCourtReport({
    required CourtReport report,
    required CourtReportStatus decision,
    String resolutionNote = '',
  }) async {
    if (decision == CourtReportStatus.pending) {
      throw const BackcourtException('처리 상태를 선택해주세요.');
    }
    final requestRef = _firestore
        .collection('court_name_requests')
        .doc(report.id);
    final courtRef = _firestore.collection('courts').doc(report.courtId);
    final eventRef = _firestore.collection('notification_events').doc();
    await _firestore.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestRef);
      if (!requestSnapshot.exists) {
        throw const BackcourtException('이미 삭제된 제보예요.');
      }
      final requestData = requestSnapshot.data()!;
      final currentStatus = CourtReportStatus.fromValue(requestData['status']);
      if (currentStatus == CourtReportStatus.approved ||
          currentStatus == CourtReportStatus.rejected) {
        throw const BackcourtException('이미 처리가 끝난 제보예요.');
      }

      final update = <String, Object?>{
        'status': decision.value,
        'resolutionNote': resolutionNote.trim(),
        'reviewedBy': currentUid,
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.update(requestRef, update);
      transaction.set(
        eventRef,
        _notificationEventData(
          type: AppNotificationType.courtReport,
          title: '코트 제보 처리',
          body: decision == CourtReportStatus.approved
              ? '제보한 내용이 반영됐어요.'
              : decision == CourtReportStatus.onHold
              ? '제보한 내용을 확인 중이에요.'
              : '제보한 내용이 반려됐어요.',
          courtId: report.courtId,
          entityId: report.id,
        ),
      );

      if (decision != CourtReportStatus.approved) return;
      final reportType = CourtReportType.fromValue(requestData['reportType']);
      final courtUpdate = <String, Object?>{
        'updatedAt': FieldValue.serverTimestamp(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'statusUpdatedBy': currentUid,
      };
      switch (reportType) {
        case CourtReportType.name:
          final requestedName =
              (requestData['requestedName'] as String?)?.trim() ?? '';
          if (requestedName.length < 2) {
            throw const BackcourtException('변경할 코트명이 올바르지 않아요.');
          }
          courtUpdate.addAll({
            'name': requestedName,
            'nameSource': 'operator',
            'nameUpdatedAt': FieldValue.serverTimestamp(),
            'nameUpdatedBy': currentUid,
          });
        case CourtReportType.duplicate:
          courtUpdate.addAll({
            'status': 'duplicate',
            'statusReason': resolutionNote.trim().isEmpty
                ? requestData['reason'] as String? ?? ''
                : resolutionNote.trim(),
          });
        case CourtReportType.closed:
          courtUpdate.addAll({
            'status': 'closed',
            'statusReason': resolutionNote.trim().isEmpty
                ? requestData['reason'] as String? ?? ''
                : resolutionNote.trim(),
          });
      }
      transaction.update(courtRef, courtUpdate);
    });
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _monthKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}';

  String _weekKey(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return _dateKey(monday);
  }

  Future<CheckinRecord> checkIn({
    required CourtSummary court,
    required double actualLatitude,
    required double actualLongitude,
    required double distanceMeters,
  }) async {
    _requireSavedCourt(court);
    if (distanceMeters > 100) {
      throw BackcourtException(
        '코트에서 ${distanceMeters.round()}m 떨어져 있어요. 100m 안에서 다시 시도해주세요.',
      );
    }
    final now = DateTime.now();
    final uid = currentUid;
    final id = '${court.id}_${uid}_${_dateKey(now)}';
    final ref = _firestore.collection('checkins').doc(id);
    final profile = await getCurrentProfile();
    await _firestore.runTransaction((transaction) async {
      if ((await transaction.get(ref)).exists) {
        throw const BackcourtException('이 코트는 오늘 이미 출석했어요.');
      }
      transaction.set(ref, {
        'uid': uid,
        'displayName': profile.displayName,
        'courtId': court.id,
        'courtName': court.name,
        'actualLocation': GeoPoint(actualLatitude, actualLongitude),
        'courtLocation': GeoPoint(court.latitude, court.longitude),
        'distanceMeters': distanceMeters,
        'dateKey': _dateKey(now),
        'monthKey': _monthKey(now),
        'checkedInAt': FieldValue.serverTimestamp(),
      });
      transaction.update(_currentUserRef, {
        'checkinCount': FieldValue.increment(1),
        'lastCheckinAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(_firestore.collection('courts').doc(court.id), {
        'lastCheckinAt': FieldValue.serverTimestamp(),
        'checkinCount': FieldValue.increment(1),
      });
    });
    return CheckinRecord(
      id: id,
      uid: uid,
      courtId: court.id,
      courtName: court.name,
      displayName: profile.displayName,
      checkedInAt: now,
      distanceMeters: distanceMeters,
    );
  }

  Stream<CheckinRecord?> watchTodayCheckin(String courtId) {
    final id = '${courtId}_${currentUid}_${_dateKey(DateTime.now())}';
    return _firestore
        .collection('checkins')
        .doc(id)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.exists ? CheckinRecord.fromDocument(snapshot) : null,
        );
  }

  Future<CheckinRecord?> latestEligibleCheckin(String courtId) async {
    final now = DateTime.now();
    CheckinRecord? latest;
    for (var daysAgo = 0; daysAgo <= 2; daysAgo++) {
      final date = now.subtract(Duration(days: daysAgo));
      final id = '${courtId}_${currentUid}_${_dateKey(date)}';
      final snapshot = await _firestore.collection('checkins').doc(id).get();
      if (!snapshot.exists) continue;
      final record = CheckinRecord.fromDocument(snapshot);
      if (now.difference(record.checkedInAt) <= reviewWindow &&
          (latest == null || record.checkedInAt.isAfter(latest.checkedInAt))) {
        latest = record;
      }
    }
    return latest;
  }

  Stream<List<RankingEntry>> watchMonthlyRanking() {
    final month = _monthKey(DateTime.now());
    return _firestore
        .collection('checkins')
        .where('monthKey', isEqualTo: month)
        .limit(500)
        .snapshots()
        .map((snapshot) {
          final counts = <String, RankingEntry>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final uid = data['uid'] as String;
            final previous = counts[uid];
            counts[uid] = RankingEntry(
              uid: uid,
              displayName: data['displayName'] as String? ?? '플레이어',
              count: (previous?.count ?? 0) + 1,
            );
          }
          final result = counts.values.toList()
            ..sort((a, b) => b.count.compareTo(a.count));
          return result.take(20).toList(growable: false);
        });
  }

  Stream<int> watchMyMonthlyCheckinCount() {
    final month = _monthKey(DateTime.now());
    return _firestore
        .collection('checkins')
        .where('uid', isEqualTo: currentUid)
        .where('monthKey', isEqualTo: month)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  Stream<int> watchMyMonthlyCourtCheckinCount(String courtId) {
    final month = _monthKey(DateTime.now());
    return _firestore
        .collection('checkins')
        .where('uid', isEqualTo: currentUid)
        .where('monthKey', isEqualTo: month)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((document) => document.data()['courtId'] == courtId)
              .length,
        );
  }

  Stream<ActivePlaySession?> watchActivePlaySession() => _firestore
      .collection('active_play_sessions')
      .doc(currentUid)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.exists ? ActivePlaySession.fromDocument(snapshot) : null,
      );

  Stream<List<MonthlyPlayStat>> watchMonthlyPlayRanking(CourtSummary court) {
    return watchCourtPlayRanking(court, CourtRankingPeriod.month);
  }

  Stream<List<MonthlyPlayStat>> watchCourtPlayRanking(
    CourtSummary court,
    CourtRankingPeriod period,
  ) {
    final now = DateTime.now();
    final (collection, periodKey) = switch (period) {
      CourtRankingPeriod.all => ('court_play_stats', 'all'),
      CourtRankingPeriod.month => ('monthly_play_stats', _monthKey(now)),
      CourtRankingPeriod.week => ('weekly_play_stats', _weekKey(now)),
    };
    final scopeKey = '${periodKey}_${court.id}';
    return _firestore
        .collection(collection)
        .where('scopeKey', isEqualTo: scopeKey)
        .orderBy('totalMinutes', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          final result =
              snapshot.docs.map(MonthlyPlayStat.fromDocument).toList()
                ..sort((a, b) {
                  final minutes = b.totalMinutes.compareTo(a.totalMinutes);
                  return minutes != 0
                      ? minutes
                      : a.displayName.compareTo(b.displayName);
                });
          return result.take(20).toList(growable: false);
        });
  }

  Future<void> startPlaySession({required CourtSummary court}) async {
    _requireSavedCourt(court);
    final now = DateTime.now();
    final checkinId = '${court.id}_${currentUid}_${_dateKey(now)}';
    final checkin = await _firestore
        .collection('checkins')
        .doc(checkinId)
        .get();
    if (!checkin.exists) {
      throw const BackcourtException('이 코트에서 GPS 출석 후 시작할 수 있어요.');
    }

    final profile = await getCurrentProfile();
    final activeRef = _firestore
        .collection('active_play_sessions')
        .doc(currentUid);
    await _firestore.runTransaction((transaction) async {
      if ((await transaction.get(activeRef)).exists) {
        throw const BackcourtException('이미 진행 중인 운동 기록이 있어요.');
      }
      transaction.set(activeRef, {
        'uid': currentUid,
        'checkinId': checkinId,
        'displayName': profile.displayName,
        'courtId': court.id,
        'courtName': court.name,
        'monthKey': _monthKey(now),
        'weekKey': _weekKey(now),
        'username': profile.username,
        'photoUrl': profile.photoUrl,
        'startedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<int> endPlaySession() async {
    final activeRef = _firestore
        .collection('active_play_sessions')
        .doc(currentUid);
    final historyRef = _firestore.collection('play_sessions').doc();
    var recordedMinutes = 0;

    await _firestore.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(activeRef);
      if (!activeSnapshot.exists) {
        throw const BackcourtException('진행 중인 운동 기록이 없어요.');
      }
      final data = activeSnapshot.data()!;
      final startedAt = dateTimeFromFirestore(data['startedAt']);
      if (startedAt == null) {
        throw const BackcourtException('시작 시간을 확인하고 있어요. 잠시 후 다시 눌러주세요.');
      }

      final now = DateTime.now();
      recordedMinutes = now.difference(startedAt).inMinutes.clamp(1, 720);
      final monthKey = data['monthKey'] as String? ?? _monthKey(startedAt);
      final weekKey = data['weekKey'] as String? ?? _weekKey(startedAt);
      final courtId = data['courtId'] as String;
      final courtName = data['courtName'] as String? ?? '농구 코트';
      final monthScopeKey = '${monthKey}_$courtId';
      final weekScopeKey = '${weekKey}_$courtId';
      final allScopeKey = 'all_$courtId';
      final monthStatRef = _firestore
          .collection('monthly_play_stats')
          .doc('${monthScopeKey}_$currentUid');
      final weekStatRef = _firestore
          .collection('weekly_play_stats')
          .doc('${weekScopeKey}_$currentUid');
      final allStatRef = _firestore
          .collection('court_play_stats')
          .doc('${allScopeKey}_$currentUid');
      final monthStatSnapshot = await transaction.get(monthStatRef);
      final weekStatSnapshot = await transaction.get(weekStatRef);
      final allStatSnapshot = await transaction.get(allStatRef);

      Map<String, dynamic> statData(
        DocumentSnapshot<Map<String, dynamic>> snapshot,
        String scopeKey, [
        Map<String, dynamic> periodData = const {},
      ]) {
        final previous = snapshot.data();
        return {
          'uid': currentUid,
          'displayName': data['displayName'] as String? ?? '플레이어',
          'username': data['username'],
          'photoUrl': data['photoUrl'],
          ...periodData,
          'scopeKey': scopeKey,
          'courtId': courtId,
          'courtName': courtName,
          'totalMinutes':
              ((previous?['totalMinutes'] as num?)?.toInt() ?? 0) +
              recordedMinutes,
          'sessionCount':
              ((previous?['sessionCount'] as num?)?.toInt() ?? 0) + 1,
          'lastSessionId': historyRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        };
      }

      transaction.set(
        monthStatRef,
        statData(monthStatSnapshot, monthScopeKey, {'monthKey': monthKey}),
      );
      transaction.set(
        weekStatRef,
        statData(weekStatSnapshot, weekScopeKey, {'weekKey': weekKey}),
      );
      transaction.set(allStatRef, statData(allStatSnapshot, allScopeKey));
      transaction.set(historyRef, {
        ...data,
        'weekKey': weekKey,
        'endedAt': FieldValue.serverTimestamp(),
        'durationMinutes': recordedMinutes,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.delete(activeRef);
    });
    return recordedMinutes;
  }

  Stream<List<ReviewRecord>> watchReviews(String courtId) => _firestore
      .collection('reviews')
      .where('courtId', isEqualTo: courtId)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(ReviewRecord.fromDocument).toList());

  Future<void> createReview({
    required CourtSummary court,
    required int rating,
    required String text,
    required String courtCondition,
    required String lighting,
    required String netCondition,
    required String crowdLevel,
    required List<XFile> images,
    XFile? video,
  }) async {
    _requireSavedCourt(court);
    final checkin = await latestEligibleCheckin(court.id);
    if (checkin == null) {
      throw const BackcourtException('이 코트에서 최근 48시간 내 GPS 출석이 필요해요.');
    }
    final profile = await getCurrentProfile();
    final ref = _firestore.collection('reviews').doc();
    final files = <({XFile file, String type})>[
      for (final image in images) (file: image, type: 'image'),
      if (video != null) (file: video, type: 'video'),
    ];
    final media = await _uploadFiles(
      files: files,
      folder: 'users/$currentUid/reviews/${ref.id}',
    );
    final editableUntil = checkin.checkedInAt.add(reviewWindow);
    final batch = _firestore.batch();
    batch.set(ref, {
      'uid': currentUid,
      'authorName': profile.displayName,
      'authorUsername': profile.username,
      'authorPhotoUrl': profile.photoUrl,
      'courtId': court.id,
      'courtName': court.name,
      'location': GeoPoint(court.latitude, court.longitude),
      'checkinId': checkin.id,
      'rating': rating,
      'text': text.trim(),
      'courtCondition': courtCondition,
      'lighting': lighting,
      'netCondition': netCondition,
      'crowdLevel': crowdLevel,
      'crowdTime': Timestamp.fromDate(DateTime.now()),
      'media': media.map((item) => item.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'editableUntil': Timestamp.fromDate(editableUntil),
    });
    batch.update(_firestore.collection('courts').doc(court.id), {
      'reviewCount': FieldValue.increment(1),
      'ratingSum': FieldValue.increment(rating),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Stream<List<CommentRecord>> watchComments(String postId) => _firestore
      .collection('comments')
      .where('postId', isEqualTo: postId)
      .orderBy('createdAt')
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(CommentRecord.fromDocument)
            .toList(growable: false),
      );

  Future<void> createComment({
    required PostRecord post,
    required String text,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || cleanText.length > 500) {
      throw const BackcourtException('댓글은 1~500자로 입력해주세요.');
    }
    final postRef = _firestore.collection('posts').doc(post.id);
    final postSnapshot = await postRef.get();
    if (!postSnapshot.exists) throw const BackcourtException('삭제된 게시물이에요.');
    final profile = await getCurrentProfile();
    final commentRef = _firestore.collection('comments').doc();
    final batch = _firestore.batch();
    batch.set(commentRef, {
      'postId': post.id,
      'postOwnerUid': post.uid,
      'courtId': post.courtId,
      'uid': currentUid,
      'authorName': profile.displayName,
      'authorPhotoUrl': profile.photoUrl,
      'text': cleanText,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(postRef, {
      'commentCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (post.uid != currentUid) {
      batch.set(
        _firestore.collection('notification_events').doc(),
        _notificationEventData(
          type: AppNotificationType.comment,
          title: '새 댓글',
          body: '${profile.displayName} · $cleanText',
          courtId: post.courtId,
          entityId: commentRef.id,
        ),
      );
    }
    await batch.commit();
  }

  Future<void> deleteComment(CommentRecord comment) async {
    if (comment.uid != currentUid) {
      throw const BackcourtException('내 댓글만 삭제할 수 있어요.');
    }
    final commentRef = _firestore.collection('comments').doc(comment.id);
    final postRef = _firestore.collection('posts').doc(comment.postId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(commentRef);
      if (!snapshot.exists) return;
      transaction.delete(commentRef);
      final postSnapshot = await transaction.get(postRef);
      if (postSnapshot.exists) {
        final count =
            (postSnapshot.data()?['commentCount'] as num?)?.toInt() ?? 0;
        transaction.update(postRef, {
          'commentCount': count > 0 ? count - 1 : 0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> deletePost(PostRecord post) async {
    if (post.uid != currentUid) {
      throw const BackcourtException('내 게시물만 삭제할 수 있어요.');
    }
    final comments = await _firestore
        .collection('comments')
        .where('postId', isEqualTo: post.id)
        .limit(400)
        .get();
    final batch = _firestore.batch();
    for (final comment in comments.docs) {
      batch.delete(comment.reference);
    }
    batch.delete(_firestore.collection('posts').doc(post.id));
    batch.update(_currentUserRef, {
      'postCount': FieldValue.increment(-1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> reportPost(PostRecord post, String reason) async {
    if (post.uid == currentUid) {
      throw const BackcourtException('내 게시물은 신고할 수 없어요.');
    }
    final cleanReason = reason.trim();
    if (cleanReason.length < 2 || cleanReason.length > 200) {
      throw const BackcourtException('신고 사유를 확인해주세요.');
    }
    await _firestore
        .collection('content_reports')
        .doc('${currentUid}_post_${post.id}')
        .set({
          'reporterUid': currentUid,
          'targetType': 'post',
          'targetId': post.id,
          'targetOwnerUid': post.uid,
          'reason': cleanReason,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Stream<Set<String>> watchBlockedUserIds() => _firestore
      .collection('blocked_users')
      .where('blockerUid', isEqualTo: currentUid)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => doc.data()['blockedUid'] as String?)
            .whereType<String>()
            .toSet(),
      );

  Stream<List<BlockedUserRecord>> watchBlockedUsers() => _firestore
      .collection('blocked_users')
      .where('blockerUid', isEqualTo: currentUid)
      .snapshots()
      .map((snapshot) {
        final users = snapshot.docs.map(BlockedUserRecord.fromDocument).toList();
        users.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return users;
      });

  Future<void> blockUser(String uid, {String? displayName}) async {
    if (uid == currentUid) return;
    await _firestore.collection('blocked_users').doc('${currentUid}_$uid').set({
      'blockerUid': currentUid,
      'blockedUid': uid,
      'displayName': displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : '차단한 사용자',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblockUser(String uid) =>
      _firestore.collection('blocked_users').doc('${currentUid}_$uid').delete();

  Future<void> addReviewMedia({
    required ReviewRecord review,
    required List<XFile> images,
    XFile? video,
  }) async {
    if (review.uid != currentUid) {
      throw const BackcourtException('내 리뷰에만 첨부를 추가할 수 있어요.');
    }
    if (DateTime.now().isAfter(review.editableUntil)) {
      throw const BackcourtException('출석 후 48시간이 지나 첨부를 추가할 수 없어요.');
    }
    final media = await _uploadFiles(
      files: [
        for (final image in images) (file: image, type: 'image'),
        if (video != null) (file: video, type: 'video'),
      ],
      folder: 'users/$currentUid/reviews/${review.id}',
    );
    if (media.isEmpty) return;
    await _firestore.collection('reviews').doc(review.id).update({
      'media': FieldValue.arrayUnion(
        media.map((item) => item.toMap()).toList(),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<MediaItem>> _uploadFiles({
    required List<({XFile file, String type})> files,
    required String folder,
  }) async {
    try {
      final uploaded = <MediaItem>[];
      for (final item in files) {
        uploaded.add(
          await _mediaStore.upload(
            file: item.file,
            type: item.type,
            folder: folder,
          ),
        );
      }
      return uploaded;
    } on CloudinaryMediaException catch (error) {
      throw BackcourtException(error.message);
    }
  }

  Stream<List<MeetupRecord>> watchMeetups() => _firestore
      .collection('meetups')
      .where('startsAt', isGreaterThanOrEqualTo: Timestamp.now())
      .orderBy('startsAt')
      .limit(50)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .where((doc) => doc.data()['status'] != 'cancelled')
            .map(MeetupRecord.fromDocument)
            .toList(),
      );

  Future<void> createMeetup({
    required CourtSummary court,
    required DateTime startsAt,
    required int capacity,
    required String gameType,
    required String level,
  }) async {
    _requireSavedCourt(court);
    if (startsAt.isBefore(DateTime.now())) {
      throw const BackcourtException('시작 시간 확인 필요');
    }
    if (capacity < 2 || capacity > 30) {
      throw const BackcourtException('정원 2~30명');
    }
    final meetupRef = _firestore.collection('meetups').doc();
    final batch = _firestore.batch();
    batch.set(meetupRef, {
      'courtId': court.id,
      'courtName': court.name,
      'location': GeoPoint(court.latitude, court.longitude),
      'startsAt': Timestamp.fromDate(startsAt),
      'capacity': capacity,
      'gameType': gameType,
      'level': level,
      'participantUids': [currentUid],
      'createdBy': currentUid,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_currentUserRef, {
      'meetupCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _firestore.collection('notification_events').doc(),
      _notificationEventData(
        type: AppNotificationType.meetup,
        title: '내 코트에 새 약속',
        body: '${court.name} · $gameType · $capacity명',
        courtId: court.id,
        entityId: meetupRef.id,
      ),
    );
    await batch.commit();
  }

  Future<void> toggleMeetupParticipation(MeetupRecord meetup) async {
    final ref = _firestore.collection('meetups').doc(meetup.id);
    final eventRef = _firestore.collection('notification_events').doc();
    final profile = await getCurrentProfile();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw const BackcourtException('삭제된 약속');
      final data = snapshot.data()!;
      final participants = List<String>.from(
        data['participantUids'] as List<dynamic>? ?? const [],
      );
      if (participants.remove(currentUid)) {
        transaction.update(ref, {
          'participantUids': participants,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      final capacity = (data['capacity'] as num).toInt();
      if (participants.length >= capacity) {
        throw const BackcourtException('정원 마감');
      }
      participants.add(currentUid);
      transaction.update(ref, {
        'participantUids': participants,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (meetup.createdBy != currentUid) {
        transaction.set(
          eventRef,
          _notificationEventData(
              type: AppNotificationType.meetupJoin,
              title: '약속 참가',
              body: '${profile.displayName}님이 ${meetup.courtName} 약속에 참가했어요.',
              courtId: meetup.courtId,
              entityId: meetup.id,
          ),
        );
      }
    });
  }

  Future<void> cancelMeetup(MeetupRecord meetup) async {
    if (meetup.createdBy != currentUid) {
      throw const BackcourtException('내가 만든 약속만 취소할 수 있어요.');
    }
    final ref = _firestore.collection('meetups').doc(meetup.id);
    final eventRef = _firestore.collection('notification_events').doc();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists || snapshot.data()?['status'] == 'cancelled') {
        throw const BackcourtException('이미 취소된 약속이에요.');
      }
      transaction.update(ref, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(
        eventRef,
        _notificationEventData(
          type: AppNotificationType.meetupCancelled,
          title: '약속 취소',
          body: '${meetup.courtName} 약속이 취소됐어요.',
          courtId: meetup.courtId,
          entityId: meetup.id,
        ),
      );
    });
  }

  Stream<List<LiveCourtStatus>> watchLiveCourtStatuses() => _firestore
      .collection('live_court_statuses')
      .where('expiresAt', isGreaterThan: Timestamp.now())
      .orderBy('expiresAt')
      .limit(200)
      .snapshots()
      .map((snapshot) {
        final statuses = snapshot.docs
            .map(LiveCourtStatus.fromDocument)
            .where((status) => status.isActive)
            .toList();
        statuses.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return statuses;
      });

  Future<void> publishLiveCourtStatus({
    required CourtSummary court,
    required LiveCourtActivity activity,
    required int playerCount,
    required int neededPlayers,
    required double distanceMeters,
  }) async {
    _requireSavedCourt(court);
    if (distanceMeters > 100) {
      throw BackcourtException(
        '코트에서 ${distanceMeters.round()}m 떨어져 있어요. 100m 안에서 다시 시도해주세요.',
      );
    }
    if (playerCount < 0 || playerCount > 30) {
      throw const BackcourtException('현재 인원은 0명부터 30명까지 입력할 수 있어요.');
    }
    if (neededPlayers < 0 || neededPlayers > 20) {
      throw const BackcourtException('필요 인원은 20명까지 입력할 수 있어요.');
    }

    final now = DateTime.now();
    final profile = await getCurrentProfile();
    final ref = _firestore.collection('live_court_statuses').doc(currentUid);
    final eventRef = _firestore.collection('notification_events').doc();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final previous = snapshot.data();
      final previousExpiresAt = dateTimeFromFirestore(previous?['expiresAt']);
      final isFreshSignal =
          previous == null ||
          previousExpiresAt == null ||
          !previousExpiresAt.isAfter(now);
      final sameCourt = previous?['courtId'] == court.id;
      final previousArrivals = sameCourt && !isFreshSignal
          ? List<String>.from(
              previous['arrivalUids'] as List<dynamic>? ?? const [],
            )
          : <String>[];

      transaction.set(ref, {
        'uid': currentUid,
        'displayName': profile.displayName,
        'username': profile.username ?? '',
        'photoUrl': profile.photoUrl ?? '',
        'courtId': court.id,
        'courtName': court.name,
        'location': GeoPoint(court.latitude, court.longitude),
        'activity': activity.value,
        'playerCount': playerCount,
        'neededPlayers': activity == LiveCourtActivity.looking
            ? neededPlayers
            : 0,
        'distanceMeters': distanceMeters,
        'arrivalUids': previousArrivals,
        'startedAt': isFreshSignal || !sameCourt
            ? FieldValue.serverTimestamp()
            : previous['startedAt'],
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(minutes: 90))),
      });
      if (isFreshSignal || !sameCourt) {
        transaction.update(_currentUserRef, {
          'liveCourtCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(
          eventRef,
          _notificationEventData(
            type: AppNotificationType.live,
            title: '내 코트 LIVE',
            body: '${court.name} · ${activity.label} · $playerCount명',
            courtId: court.id,
            entityId: ref.id,
          ),
        );
      }
    });
  }

  Future<void> endLiveCourtStatus() =>
      _firestore.collection('live_court_statuses').doc(currentUid).delete();

  Future<void> toggleLiveCourtArrival(LiveCourtStatus status) async {
    if (status.uid == currentUid) {
      throw const BackcourtException('내 LIVE 신호에는 합류할 필요가 없어요.');
    }
    final ref = _firestore.collection('live_court_statuses').doc(status.id);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw const BackcourtException('종료된 LIVE 신호예요.');
      }
      final data = snapshot.data()!;
      final expiresAt = dateTimeFromFirestore(data['expiresAt']);
      if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
        throw const BackcourtException('이미 만료된 LIVE 신호예요.');
      }
      final arrivals = List<String>.from(
        data['arrivalUids'] as List<dynamic>? ?? const [],
      );
      if (!arrivals.remove(currentUid)) {
        if (arrivals.length >= 30) {
          throw const BackcourtException('합류 예정 인원이 가득 찼어요.');
        }
        arrivals.add(currentUid);
      }
      transaction.update(ref, {
        'arrivalUids': arrivals,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<List<PostRecord>> watchPosts() => _firestore
      .collection('posts')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(PostRecord.fromDocument).toList());

  Stream<List<PostRecord>> watchMyPosts() => _firestore
      .collection('posts')
      .where('uid', isEqualTo: currentUid)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(PostRecord.fromDocument).toList());

  Future<void> createPost({
    required CourtSummary court,
    required String text,
    required List<XFile> images,
    XFile? video,
  }) async {
    _requireSavedCourt(court);
    if (text.trim().isEmpty && images.isEmpty && video == null) {
      throw const BackcourtException('글이나 사진·영상을 추가해주세요.');
    }
    final profile = await getCurrentProfile();
    final ref = _firestore.collection('posts').doc();
    final media = await _uploadFiles(
      files: [
        for (final image in images) (file: image, type: 'image'),
        if (video != null) (file: video, type: 'video'),
      ],
      folder: 'users/$currentUid/posts/${ref.id}',
    );
    final batch = _firestore.batch();
    batch.set(ref, {
      'uid': currentUid,
      'authorName': profile.displayName,
      'authorUsername': profile.username,
      'authorPhotoUrl': profile.photoUrl,
      'courtId': court.id,
      'courtName': court.name,
      'location': GeoPoint(court.latitude, court.longitude),
      'text': text.trim(),
      'media': media.map((item) => item.toMap()).toList(),
      'likeUids': <String>[],
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_currentUserRef, {
      'postCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> togglePostLike(PostRecord post) async {
    final ref = _firestore.collection('posts').doc(post.id);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw const BackcourtException('삭제된 게시물이에요.');
      final likes = List<String>.from(
        snapshot.data()!['likeUids'] as List<dynamic>? ?? const [],
      );
      if (!likes.addIfAbsent(currentUid)) likes.remove(currentUid);
      transaction.update(ref, {
        'likeUids': likes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> deleteAccount() async {
    final lastSignIn = currentUser.metadata.lastSignInTime;
    if (lastSignIn == null ||
        DateTime.now().difference(lastSignIn) > const Duration(minutes: 4)) {
      throw const BackcourtException('안전한 탈퇴를 위해 로그아웃 후 다시 로그인해주세요.');
    }

    final uid = currentUid;
    final profile = await getCurrentProfile();
    final deleteQueries = <Query<Map<String, dynamic>>>[
      _firestore.collection('posts').where('uid', isEqualTo: uid),
      _firestore.collection('comments').where('uid', isEqualTo: uid),
      _firestore.collection('reviews').where('uid', isEqualTo: uid),
      _firestore.collection('checkins').where('uid', isEqualTo: uid),
      _firestore.collection('play_sessions').where('uid', isEqualTo: uid),
      _firestore.collection('monthly_play_stats').where('uid', isEqualTo: uid),
      _firestore.collection('weekly_play_stats').where('uid', isEqualTo: uid),
      _firestore.collection('court_play_stats').where('uid', isEqualTo: uid),
      _firestore.collection('favorite_courts').where('uid', isEqualTo: uid),
      _firestore
          .collection('blocked_users')
          .where('blockerUid', isEqualTo: uid),
      _firestore.collection('notifications').where('targetUid', isEqualTo: uid),
      _firestore
          .collection('content_reports')
          .where('reporterUid', isEqualTo: uid),
      _firestore.collection('meetups').where('createdBy', isEqualTo: uid),
    ];
    final documents = <DocumentReference<Map<String, dynamic>>>{};
    for (final query in deleteQueries) {
      final snapshot = await query.limit(400).get();
      documents.addAll(snapshot.docs.map((doc) => doc.reference));
    }

    final joinedMeetups = await _firestore
        .collection('meetups')
        .where('participantUids', arrayContains: uid)
        .limit(200)
        .get();
    final batch = _firestore.batch();
    for (final doc in joinedMeetups.docs) {
      if (doc.data()['createdBy'] != uid) {
        batch.update(doc.reference, {
          'participantUids': FieldValue.arrayRemove([uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    for (final ref in documents) {
      batch.delete(ref);
    }
    batch.delete(_firestore.collection('active_play_sessions').doc(uid));
    if (profile.username?.isNotEmpty == true) {
      batch.delete(_firestore.collection('usernames').doc(profile.username));
    }
    batch.delete(_firestore.collection('private_users').doc(uid));
    batch.delete(_firestore.collection('users').doc(uid));
    await batch.commit();

    try {
      await currentUser.delete();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login') {
        throw const BackcourtException('로그아웃 후 다시 로그인해서 탈퇴를 완료해주세요.');
      }
      rethrow;
    }
  }
}

extension on List<String> {
  bool addIfAbsent(String value) {
    if (contains(value)) return false;
    add(value);
    return true;
  }
}
