import "platform_args_stub.dart" if (dart.library.io) "platform_args_io.dart";

List<String> executableArgs() => getExecutableArgs();
