import 'adult_consent_stub.dart' if (dart.library.io) 'adult_consent_io.dart'
    as impl;

abstract class AdultConsent {
  Future<bool> isAccepted();
  Future<void> accept();
}

class LocalAdultConsent implements AdultConsent {
  @override
  Future<bool> isAccepted() => impl.isAccepted();
  @override
  Future<void> accept() => impl.accept();
}
