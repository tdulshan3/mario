/// Mario entrypoint — initialises Firebase, window manager (Linux), DI, then runs MarioApp.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import 'app.dart';
import 'core/services/auth_service.dart';
import 'core/services/drive_service.dart';
import 'core/services/ocr_service.dart';
import 'core/services/sync_service.dart';
import 'firebase_options.dart';
import 'platform/web/auth_service_web.dart';
import 'platform/web/ocr_service_web.dart';

// Conditional imports — Linux dart:io implementations on native; web stubs in browser.
import 'platform/linux/auth_service_linux.dart' if (dart.library.html) 'platform/web/auth_service_web.dart' as linux_auth;
import 'platform/linux/ocr_service_linux.dart' if (dart.library.html) 'platform/web/ocr_service_web.dart' as linux_ocr;
import 'platform/linux/window_config_linux.dart' if (dart.library.html) 'platform/web/_window_stub.dart' as linux_win;

const _linuxClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const _linuxClientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    await linux_win.configureLinuxWindow();
  }

  _registerServices();

  runApp(const ProviderScope(child: MarioApp()));
}

void _registerServices() {
  final getIt = GetIt.instance;
  if (kIsWeb) {
    getIt.registerSingleton<AuthService>(AuthServiceWeb());
    getIt.registerSingleton<OcrService>(OcrServiceWeb());
  } else if (defaultTargetPlatform == TargetPlatform.linux) {
    getIt.registerSingleton<AuthService>(linux_auth.AuthServiceLinux(
      clientId: _linuxClientId,
      clientSecret: _linuxClientSecret,
    ));
    getIt.registerSingleton<OcrService>(linux_ocr.OcrServiceLinux());
  } else {
    // Fallback for desktop platforms not yet implemented (mac/win) — use web stubs.
    getIt.registerSingleton<AuthService>(AuthServiceWeb());
    getIt.registerSingleton<OcrService>(OcrServiceWeb());
  }

  getIt.registerSingleton<FirebaseFirestore>(FirebaseFirestore.instance);
  getIt.registerSingleton<DriveService>(DriveService(getIt<AuthService>()));
  getIt.registerSingleton<SyncService>(
    SyncService(getIt<FirebaseFirestore>(), getIt<DriveService>()),
  );
}
