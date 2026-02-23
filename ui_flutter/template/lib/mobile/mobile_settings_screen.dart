import "dart:async";

import "package:flutter/material.dart";

import "../theme/tokens.dart";
import "mobile_prefs.dart";
import "mobile_store.dart";
import "mobile_usage.dart";

class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({super.key});

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  late final TextEditingController _blockMinutes;
  Timer? _saveDebounce;

  bool _permLoading = false;
  bool _usageAccess = false;

  bool _wiping = false;

  @override
  void initState() {
    super.initState();
    _blockMinutes = TextEditingController(text: MobilePrefs.defaultBlockMinutes.toString());
    _loadPrefsAndPerms();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _blockMinutes.dispose();
    super.dispose();
  }

  Future<void> _loadPrefsAndPerms() async {
    setState(() => _permLoading = true);
    try {
      final bm = await MobilePrefs.getBlockMinutes();
      final perm = await MobileUsage.instance.hasPermission();
      if (!mounted) return;
      setState(() {
        _blockMinutes.text = bm.toString();
        _usageAccess = perm;
      });
    } finally {
      if (mounted) setState(() => _permLoading = false);
    }
  }

  void _scheduleSaveBlockMinutes() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 650), () async {
      final v = int.tryParse(_blockMinutes.text.trim());
      if (v == null) return;
      try {
        await MobilePrefs.setBlockMinutes(v);
      } catch (_) {
        // ignore
      }
    });
  }

  Future<void> _wipeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Wipe all data?"),
        content: const Text("This deletes all local blocks and reviews on this phone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Wipe")),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _wiping = true);
    try {
      await MobileStore.instance.wipeAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wiped.")));
    } finally {
      if (mounted) setState(() => _wiping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RecorderTokens.space4),
              child: Row(
                children: [
                  Icon(_usageAccess ? Icons.check_circle_outline : Icons.lock_outline),
                  const SizedBox(width: RecorderTokens.space3),
                  Expanded(
                    child: Text(
                      _usageAccess ? "Usage Access: ON" : "Usage Access: OFF (required)",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: RecorderTokens.space3),
                  OutlinedButton(
                    onPressed: _permLoading
                        ? null
                        : () async {
                            await MobileUsage.instance.openPermissionSettings();
                          },
                    child: const Text("Open"),
                  ),
                  const SizedBox(width: RecorderTokens.space2),
                  IconButton(
                    onPressed: _permLoading ? null : _loadPrefsAndPerms,
                    icon: _permLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    tooltip: "Refresh",
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: RecorderTokens.space4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RecorderTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Blocks", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: RecorderTokens.space3),
                  TextField(
                    controller: _blockMinutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Block length (minutes)",
                      helperText: "Default 45. Changing this affects newly generated blocks.",
                    ),
                    onChanged: (_) => _scheduleSaveBlockMinutes(),
                    onSubmitted: (_) => _scheduleSaveBlockMinutes(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: RecorderTokens.space4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RecorderTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Data", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: RecorderTokens.space3),
                  FilledButton.icon(
                    onPressed: _wiping ? null : _wipeAll,
                    icon: const Icon(Icons.delete_forever),
                    label: Text(_wiping ? "Wiping…" : "Wipe all"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
