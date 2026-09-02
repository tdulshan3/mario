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
import 'core/demo/demo_data.dart';
import 'core/services/ai/ai_artifact_store.dart';
import 'core/services/ai/llm_provider_config.dart';
import 'core/services/ai/llm_service.dart';
import 'core/services/ai/web_search_service.dart';
import 'core/services/asset_cache.dart';
import 'core/services/asset_sync_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/drive_service.dart';
import 'core/services/mario_firestore.dart';
import 'core/services/ocr_service.dart';
import 'core/services/page_content_cache.dart';
import 'core/services/page_content_repository.dart';
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
    try {
      _linuxSecrets = await SecretsLoader.load();
    } catch (_) {
      // Demo mode carries on without them; every other build still fails
      // below, where the missing credentials get a message worth reading.
      if (!kDemoMode) rethrow;
    }
    final webOpts = DefaultFirebaseOptions.web;
    _linuxTokenStore = fd.VolatileStore();
    fd.FirebaseAuth.initialize(webOpts.apiKey, _linuxTokenStore!);
    fd.Firestore.initialize(webOpts.projectId);
  }

  _registerServices(isLinuxNative);

  // Load the image-asset index before the first editor can mount. It is one
  // small JSON read, and having it in memory is what lets an image block
  // resolve a cached picture synchronously instead of flashing a spinner on
  // every page open. Demo mode skips it: the index lives in Drive, and demo
  // mode is defined by not going there.
  if (!kDemoMode) {
    await GetIt.I<AssetSyncService>().warmUp();
  }

  runApp(ProviderScope(
    overrides: kDemoMode ? demoOverrides() : const [],
    child: const MarioApp(),
  ));
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
    // Demo mode never signs in — its auth state is a fixture — so it must not
    // require OAuth credentials just to reach a screenshot.
    final secrets = _linuxSecrets ??
        (kDemoMode
            ? const MarioSecrets(desktopClientId: '', desktopClientSecret: '')
            : null);
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
  getIt.registerSingleton<AssetCache>(AssetCache());
  getIt.registerSingleton<AssetSyncService>(
      AssetSyncService(getIt<DriveService>(), getIt<AssetCache>()));
  getIt.registerSingleton<PageContentCache>(PageContentCache());
  getIt.registerSingleton<PageContentRepository>(PageContentRepository(
      getIt<DriveService>(), getIt<PageContentCache>()));
  // AI. The backend list is loaded lazily by aiConfigsProvider rather than
  // here, so a slow or absent keyring cannot delay first paint — and the app
  // is entirely usable with no model configured at all.
  getIt.registerSingleton<AiBackends>(AiBackends(LlmProviderStore()));
  getIt.registerSingleton<LlmService>(LlmService(getIt<AiBackends>()));
  getIt.registerSingleton<WebSearchService>(WebSearchService());
  getIt.registerSingleton<AiArtifactStore>(
      AiArtifactStore(getIt<DriveService>()));

  getIt.registerSingleton<SyncService>(SyncService(
    getIt<MarioFirestore>(),
    getIt<PageContentRepository>(),
    getIt<AiArtifactStore>(),
  ));
  getIt.registerSingleton<VoiceService>(VoiceServiceImpl());
}
