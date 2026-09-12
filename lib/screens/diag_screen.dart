import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/diag.dart';
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
            title: const Text('Diagnostics'),
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
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: d.clear,
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                color: Palette.bg2,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fast hearing (15 s window)', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Turn off if hearing crashes or misses words', style: TextStyle(color: Palette.muted)),
                      value: d.fastWhisper,
                      activeColor: Palette.you,
                      onChanged: d.setFast,
                    ),
                    Row(
                      children: [
                        const Text('Hearing threads', style: TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        for (final n in [2, 4, 6, 8])
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              label: Text('$n'),
                              selected: d.whisperThreads == n,
                              selectedColor: Palette.you.withOpacity(0.3),
                              onSelected: (_) => d.setThreads(n),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
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
