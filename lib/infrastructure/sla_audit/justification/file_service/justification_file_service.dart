export 'justification_file_service_interface.dart';

export 'justification_file_service_stub.dart'
    if (dart.library.js_interop) 'justification_file_service_web.dart'
    show createJustificationFileService;
