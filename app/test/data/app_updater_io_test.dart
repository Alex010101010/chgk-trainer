import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:chgk_trainer/data/app_updater.dart';
import 'package:chgk_trainer/data/app_updater_io.dart';

// Real HTTP and files, only redirect release URLs to the local test server.
class LocalClient extends http.BaseClient {
  final int port;
  final IOClient inner = IOClient(HttpClient());
  bool closed = false;
  LocalClient(this.port);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(http.Request(
          'GET',
          Uri.parse('http://127.0.0.1:$port/'
              '${request.url.path.contains("manifest") ? "manifest" : "apk"}')));
  @override
  void close() {
    closed = true;
    inner.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This suite deliberately exercises loopback HTTP, not Flutter's 400 stub.
  final originalOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = null);
  tearDown(() => HttpOverrides.global = originalOverrides);
  for (final scenario in ['success', 'corrupt', 'cancel', 'timeout']) {
    test('real HTTP download: $scenario', () async {
      PackageInfo.setMockInitialValues(
          appName: 'test',
          packageName: 'test',
          version: '0.1.0',
          buildNumber: '48',
          buildSignature: '');
      final dir = await Directory.systemTemp.createTemp('chgk-update-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => dir.path);
      final payload = List<int>.generate(24000, (i) => i % 256);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        try {
          if (request.uri.path == '/manifest') {
            request.response.write(jsonEncode({
              'app_build': 49,
              'apk_url': 'https://example.test/app.apk',
              'size': payload.length,
              'sha256': scenario == 'corrupt'
                  ? 'bad'
                  : sha256.convert(payload).toString(),
            }));
          } else {
            request.response.contentLength = payload.length;
            request.response.add(payload.sublist(0, 12000));
            await request.response.flush();
            await Future<void>.delayed(Duration(
                milliseconds:
                    scenario == 'timeout' || scenario == 'cancel' ? 300 : 30));
            request.response.add(payload.sublist(12000));
          }
          await request.response.close();
        } catch (_) {/* Cancellation closes the peer connection. */}
      });
      final clients = <LocalClient>[];
      var opened = 0;
      final updater = IoAppUpdater(
          clientFactory: () {
            final client = LocalClient(server.port);
            clients.add(client);
            return client;
          },
          downloadTimeout:
              Duration(milliseconds: scenario == 'timeout' ? 100 : 2000),
          openApk: (path) async {
            expect(await File(path).readAsBytes(), payload);
            opened++;
            return OpenResult(type: ResultType.done, message: 'done');
          });
      final token = UpdateCancellation();
      final events = <UpdateProgress>[];
      try {
        expect((await updater.check()).status, AppUpdateStatus.available);
        final result = await updater.install(
            cancellation: token,
            onProgress: (p) {
              events.add(p);
              if (scenario == 'cancel' && p.received > 0) token.cancel();
            });
        expect(events.any((p) => p.received > 0 && p.received < payload.length),
            isTrue);
        if (scenario == 'success') {
          expect(result, isNull);
          expect(opened, 1);
          expect(
              events.map((p) => p.phase),
              containsAllInOrder([
                UpdatePhase.downloading,
                UpdatePhase.verifying,
                UpdatePhase.opening
              ]));
          expect(
              events
                  .where((p) => p.phase == UpdatePhase.downloading)
                  .last
                  .fraction,
              1);
        } else {
          expect(
              result,
              contains(scenario == 'corrupt'
                  ? 'повреждён'
                  : scenario == 'cancel'
                      ? 'отменена'
                      : '5 минут'));
          expect(opened, 0);
          expect(File('${dir.path}/update.apk').existsSync(), isFalse);
          await Future<void>.delayed(const Duration(milliseconds: 350));
          expect(opened, 0);
        }
        expect(clients.every((c) => c.closed), isTrue);
      } finally {
        await server.close(force: true);
        await dir.delete(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'), null);
      }
    });
  }
}
