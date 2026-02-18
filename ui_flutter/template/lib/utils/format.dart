import "../api/core_client.dart";

String formatHHMM(String rfc3339) {
  try {
    final t = DateTime.parse(rfc3339).toLocal();
    final hh = t.hour.toString().padLeft(2, "0");
    final mm = t.minute.toString().padLeft(2, "0");
    return "$hh:$mm";
  } catch (_) {
    final parts = rfc3339.split("T");
    if (parts.length < 2) return "??:??";
    final hhmm = parts[1];
    return hhmm.length >= 5 ? hhmm.substring(0, 5) : "??:??";
  }
}

String displayEntity(String? raw) {
  final v = (raw ?? "").trim();
  if (v.isEmpty) return "(unknown)";
  if (v == "__hidden__") return "(hidden)";
  final base = v.split(RegExp(r"[\\/]+")).last;
  if (base.toLowerCase().endsWith(".exe")) {
    return base.substring(0, base.length - 4);
  }
  return base;
}

String formatDuration(int seconds) {
  final m = ((seconds + 30) / 60).floor();
  if (m < 60) return "${m}m";
  final h = (m / 60).floor();
  final rm = m % 60;
  return rm == 0 ? "${h}h" : "${h}h ${rm}m";
}

String normalizeWebTitle(String domain, String raw) {
  var t = raw.trim();
  if (t.isEmpty) return "";
  if (domain.contains("youtube.") && t.endsWith(" - YouTube")) {
    t = t.substring(0, t.length - " - YouTube".length).trim();
  }
  return t;
}

String? extractVscodeWorkspace(String windowTitle) {
  var s = windowTitle.trim();
  if (s.isEmpty) return null;

  s = s.replaceAll(RegExp(r"\s[-—–]\sVisual Studio Code.*$"), "").trim();
  if (s.isEmpty) return null;

  final parts = s.split(RegExp(r"\s[-—–]\s")).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) return parts.last;
  return parts.first;
}

String displayTopItemName(TopItem it) {
  final raw = it.name;
  final kind = it.kind;
  if (raw.trim() == "__hidden__") return "(hidden)";
  final isApp = kind == "app" || raw.contains("\\") || raw.contains("/") || raw.startsWith("pid:");
  if (!isApp) return raw;
  final base = raw.split(RegExp(r"[\\/]+")).last;
  if (base.toLowerCase().endsWith(".exe")) {
    return base.substring(0, base.length - 4);
  }
  return base;
}
