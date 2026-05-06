import 'package:flutter_test/flutter_test.dart';

import 'package:mario/platform/linux/secrets_loader.dart';

void main() {
  group('SecretsLoader.parse', () {
    test('extracts id + secret from a Google JSON blob', () {
      final secrets = SecretsLoader.parse(
        envContents: {
          'desktopclientid':
              '{"installed":{"client_id":"abc.apps","project_id":"p","client_secret":"S3cr3t","redirect_uris":["http://localhost"]}}',
        },
        environment: const {},
      );
      expect(secrets.desktopClientId, 'abc.apps');
      expect(secrets.desktopClientSecret, 'S3cr3t');
    });

    test('handles trailing junk on the JSON line', () {
      final secrets = SecretsLoader.parse(
        envContents: {
          'desktopclientid':
              '{"installed":{"client_id":"abc","client_secret":"sec"}}keep',
        },
        environment: const {},
      );
      expect(secrets.desktopClientId, 'abc');
      expect(secrets.desktopClientSecret, 'sec');
    });

    test('falls back to bare key/value pairs', () {
      final secrets = SecretsLoader.parse(
        envContents: {
          'desktopclientid': 'abc.apps',
          'desktopclientsecret': 'plain-secret',
        },
        environment: const {},
      );
      expect(secrets.desktopClientId, 'abc.apps');
      expect(secrets.desktopClientSecret, 'plain-secret');
    });

    test('process env overrides .env contents', () {
      final secrets = SecretsLoader.parse(
        envContents: {
          'desktopclientid': 'file-id',
          'desktopclientsecret': 'file-secret',
        },
        environment: const {
          'MARIO_DESKTOP_CLIENT_ID': 'env-id',
          'MARIO_DESKTOP_CLIENT_SECRET': 'env-secret',
        },
      );
      expect(secrets.desktopClientId, 'env-id');
      expect(secrets.desktopClientSecret, 'env-secret');
    });

    test('GOOGLE_* aliases are recognised', () {
      final secrets = SecretsLoader.parse(
        envContents: const {},
        environment: const {
          'GOOGLE_CLIENT_ID': 'g-id',
          'GOOGLE_CLIENT_SECRET': 'g-secret',
        },
      );
      expect(secrets.desktopClientId, 'g-id');
      expect(secrets.desktopClientSecret, 'g-secret');
    });

    test('throws when both sources are missing the secret', () {
      expect(
        () => SecretsLoader.parse(
          envContents: const {'desktopclientid': 'just-id'},
          environment: const {},
        ),
        throwsA(isA<SecretsMissingException>()),
      );
    });
  });
}
