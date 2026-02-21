import "single_instance.dart";

Future<SingleInstanceHandle?> ensureSingleInstanceImpl(List<String> _args) async {
  // Web/mobile: allow multiple instances (not applicable).
  return SingleInstanceHandle(messages: const Stream.empty(), dispose: () async {});
}

