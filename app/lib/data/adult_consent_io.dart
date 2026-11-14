import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _marker() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/adult_consent_v1');
}

Future<bool> isAccepted([File? marker]) async {
  final file = marker ?? await _marker();
  if (!await file.exists()) return false;
  return await file.readAsString() == 'accepted';
}

Future<void> accept([File? marker]) async {
  final file = marker ?? await _marker();
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.tmp');
  await temp.writeAsString('accepted', flush: true);
  await temp.rename(file.path);
}
