import "package:flutter/material.dart";

import "../theme/tokens.dart";
import "mobile_store.dart";

class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({super.key});

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  bool _wiping = false;

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

