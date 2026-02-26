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
    _blockMinutes =
        TextEditingController(text: MobilePrefs.defaultBlockMinutes.toString());
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
        title: const Text("清空全部数据？"),
        content: const Text("这会删除本机所有分段与复盘记录。"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("取消")),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("清空")),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _wiping = true);
    try {
      await MobileStore.instance.wipeAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("已清空。")));
    } finally {
      if (mounted) setState(() => _wiping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("设置")),
      body: ListView(
        padding: const EdgeInsets.all(RecorderTokens.space4),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RecorderTokens.space4),
              child: Row(
                children: [
                  Icon(_usageAccess
                      ? Icons.check_circle_outline
                      : Icons.lock_outline),
                  const SizedBox(width: RecorderTokens.space3),
                  Expanded(
                    child: Text(
                      _usageAccess ? "使用情况访问权限：已开启" : "使用情况访问权限：未开启（必须）",
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
                    child: const Text("打开系统设置"),
                  ),
                  const SizedBox(width: RecorderTokens.space1),
                  IconButton(
                    onPressed: _permLoading
                        ? null
                        : () async {
                            await MobileUsage.instance.openAppSettings();
                          },
                    icon: const Icon(Icons.info_outline),
                    tooltip: "应用信息",
                  ),
                  const SizedBox(width: RecorderTokens.space2),
                  IconButton(
                    onPressed: _permLoading ? null : _loadPrefsAndPerms,
                    icon: _permLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    tooltip: "刷新",
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
                  Text("分段", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: RecorderTokens.space3),
                  TextField(
                    controller: _blockMinutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "分段长度（分钟）",
                      helperText: "默认 45。修改只影响新生成的分段。",
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
                  Text("数据", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: RecorderTokens.space3),
                  FilledButton.icon(
                    onPressed: _wiping ? null : _wipeAll,
                    icon: const Icon(Icons.delete_forever),
                    label: Text(_wiping ? "清空中…" : "清空全部"),
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
