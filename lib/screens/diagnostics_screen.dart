import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../services/crash_log.dart';

/// Shows the on-device error/diagnostics log so any problem can be reported
/// by copying the text — no adb, no developer mode needed.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  String _log = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await CrashLog.readAll();
    if (!mounted) return;
    setState(() {
      _log = log;
      _loading = false;
    });
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _log));
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.logCopied)));
    }
  }

  Future<void> _clear() async {
    await CrashLog.clear();
    if (mounted) setState(() => _log = '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(L.errorLog),
        actions: [
          IconButton(
            tooltip: L.copyError,
            icon: const Icon(Icons.copy_rounded),
            onPressed: _log.isEmpty ? null : _copy,
          ),
          IconButton(
            tooltip: L.clearLog,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _log.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _log.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded,
                          size: 56, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(L.errorLogEmpty,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _log,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
