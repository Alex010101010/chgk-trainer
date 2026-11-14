bool _accepted = false;
Future<bool> isAccepted() async => _accepted;
Future<void> accept() async {
  _accepted = true;
}
