import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;
  bool _googleInitialized = false;

  Stream<User?> get authStateChanges => _firebaseAuth.userChanges();

  static const phoneLoginEnabled = bool.fromEnvironment(
    'ENABLE_PHONE_LOGIN',
    defaultValue: false,
  );
  static const kakaoLoginEnabled = bool.fromEnvironment(
    'ENABLE_KAKAO_LOGIN',
    defaultValue: false,
  );
  static const appleLoginEnabled = bool.fromEnvironment(
    'ENABLE_APPLE_LOGIN',
    defaultValue: false,
  );

  Future<void> signInWithApple() async {
    final appleProvider = AppleAuthProvider()..addScope('email');
    await _firebaseAuth.signInWithProvider(appleProvider);
  }

  Future<void> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await googleSignIn.initialize();
      _googleInitialized = true;
    }
    if (!googleSignIn.supportsAuthenticate()) {
      throw const AuthFlowException('이 기기에서는 Google 로그인을 사용할 수 없어요.');
    }
    final account = await googleSignIn.authenticate();
    final authentication = account.authentication;
    final idToken = authentication.idToken;
    if (idToken == null) {
      throw const AuthFlowException('Google 인증 정보를 가져오지 못했어요.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.sendEmailVerification();
  }

  Future<void> sendPasswordReset(String email) =>
      _firebaseAuth.sendPasswordResetEmail(email: email);

  Future<void> resendEmailVerification() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw const AuthFlowException('로그인이 필요해요.');
    await user.sendEmailVerification();
  }

  Future<bool> reloadEmailVerification() async {
    await _firebaseAuth.currentUser?.reload();
    return _firebaseAuth.currentUser?.emailVerified ?? false;
  }

  Future<String> sendPhoneCode(String phoneNumber) async {
    final completer = Completer<String>();
    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        await _firebaseAuth.signInWithCredential(credential);
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      codeSent: (verificationId, _) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
    );
    return completer.future.timeout(const Duration(seconds: 60));
  }

  Future<void> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    if (_googleInitialized) await GoogleSignIn.instance.signOut();
  }
}

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;
}
