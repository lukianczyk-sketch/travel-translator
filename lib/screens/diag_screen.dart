import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/diag.dart';
import '../services/native_stt.dart';
import '../theme.dart';

class DiagScreen extends StatelessWidget {
  const DiagScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Diag.instance,
      builder: (context, _) {
        final d = Diag.instance;
        return Scaffold(
          appBar: AppBar(
            title: Text('Diagnostics — v$appVersion'),
            actions: [
              IconButton(
                tooltip: 'Copy log',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: d.text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Log copied — paste it to Claude.')));
                  }
                },
              ),
              IconButton(
                tooltip: 'Pull phone system log',
                icon: const Icon(Icons.phone_android_rounded),
                onPressed: () async {
                  final l = await NativeStt.logcat();
                  for (final line in l.split('\n')) {
                    if (line.trim().isNotEmpty) Diag.instance.log('android: $line');
                  }
                },
              ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: d.clear,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SelectionArea(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: d.lines.length,
                    itemBuilder: (_, i) {
                      final l = d.lines[d.lines.length - 1 - i]; // newest first
                      final bad = l.contains('ERROR') || l.contains('error') || l.contains('Exception');
                      return Text(
                        l,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          height: 1.4,
                          color: bad ? Palette.them : Palette.text,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
