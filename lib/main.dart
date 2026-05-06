/// Mario entrypoint — initialises Firebase (web only), firedart (Linux),
/// the window/tray, then runs MarioApp.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firedart/firedart.dart' as fd;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import 'app.dart';
import 'core/services/auth_service.dart';
import 'core/services/drive_service.dart';
import 'core/services/mario_firestore.dart';
import 'core/services/ocr_service.dart';
import 'core/services/sync_service.dart';
import 'core/services/voice_service.dart';
import 'features/voice/voice_service_impl.dart';
import 'firebase_options.dart';
import 'platform/linux/firedart_client.dart';
import 'platform/linux/secrets_loader.dart';
import 'platform/web/auth_service_web.dart';
import 'platform/web/cloud_firestore_client.dart';
import 'platform/web/ocr_service_web.dart';

import 'platform/linux/auth_service_linux.dart' if (dart.library.html) 'platform/web/auth_service_web.dart' as linux_auth;
import 'platform/linux/ocr_service_linux.dart' if (dart.library.html) 'platform/web/ocr_service_web.dart' as linux_ocr;
import 'platform/linux/window_config_linux.dart' if (dart.library.html) 'platform/web/_window_stub.dart' as linux_win;

fd.TokenStore? _linuxTokenStore;
MarioSecrets? _linuxSecrets;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isLinuxNative =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  if (!isLinuxNative) {
    // Firebase Flutter has no Linux SDK; web/mobile takes the official path.
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } else {
    await linux_win.configureLinuxWindow();
    _linuxSecrets = await SecretsLoader.load();
    final webOpts = DefaultFirebaseOptions.web;
    _linuxTokenStore = fd.VolatileStore();
    fd.FirebaseAuth.initialize(webOpts.apiKey, _linuxTokenStore!);
    fd.Firestore.initialize(webOpts.projectId);
  }

  _registerServices(isLinuxNative);
  runApp(const ProviderScope(child: MarioApp()));
}

void _registerServices(bool isLinuxNative) {
  final getIt = GetIt.instance;

  if (kIsWeb) {
    getIt.registerSingleton<AuthService>(AuthServiceWeb());
    getIt.registerSingleton<OcrService>(OcrServiceWeb());
    getIt.registerSingleton<MarioFirestore>(
        CloudFirestoreClient(FirebaseFirestore.instance));
  } else if (isLinuxNative) {
    final webOpts = DefaultFirebaseOptions.web;
    final secrets = _linuxSecrets;
    if (secrets == null) {
      throw StateError(
          'No `secrets` file found in the project root. Create one with '
          '"desktop client id=" and "desktop client secret=" lines.');
    }
    getIt.registerSingleton<AuthService>(linux_auth.AuthServiceLinux(
      googleClientId: secrets.desktopClientId,
      googleClientSecret: secrets.desktopClientSecret,
      firebaseApiKey: webOpts.apiKey,
      firedartStore: _linuxTokenStore!,
    ));
    getIt.registerSingleton<OcrService>(linux_ocr.OcrServiceLinux());
    getIt.registerSingleton<MarioFirestore>(
        FiredartClient(fd.Firestore.instance));
  } else {
    // Other desktops (mac/windows) — fall back to FlutterFire if init succeeded.
    getIt.registerSingleton<AuthService>(AuthServiceWeb());
    getIt.registerSingleton<OcrService>(OcrServiceWeb());
    getIt.registerSingleton<MarioFirestore>(
        CloudFirestoreClient(FirebaseFirestore.instance));
  }

  getIt.registerSingleton<DriveService>(DriveService(getIt<AuthService>()));
  getIt.registerSingleton<SyncService>(
      SyncService(getIt<MarioFirestore>(), getIt<DriveService>()));
  getIt.registerSingleton<VoiceService>(VoiceServiceImpl());
}
