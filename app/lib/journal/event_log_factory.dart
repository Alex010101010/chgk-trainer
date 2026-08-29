/// Условие — `dart.library.js_interop`, а не `dart.library.html`: последний
/// ломается при компиляции в wasm.
export 'event_log_factory_io.dart'
    if (dart.library.js_interop) 'event_log_factory_web.dart';
