import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';

import 'screens/book_screen.dart';
import 'screens/home_screen.dart';
import 'screens/languages_screen.dart';
import 'services/book_store.dart';
import 'services/diag.dart';
import 'services/model_manager.dart';
import 'theme.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Diag.instance.init();
    FlutterError.onError = (details) {
      Diag.instance.log('ERROR (flutter): ${details.exceptionAsString()}');
      FlutterError.presentError(details);
    };
    await _boot();
  }, (e, st) {
    Diag.instance.log('ERROR (uncaught): $e');
  });
}

Future<void> _boot() async {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Palette.bg,
  ));
  await ModelManager.instance.init();
  await BookStore.instance.init();
  runApp(const TravelTranslatorApp());
}

class TravelTranslatorApp extends StatelessWidget {
  const TravelTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travel Translator',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [HomeScreen(), BookScreen(), LanguagesScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Palette.bg2,
          indicatorColor: Palette.you.withOpacity(0.18),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
              size: 30,
              color: s.contains(WidgetState.selected) ? Palette.you : Palette.muted,
            ),
          ),
        ),
        child: NavigationBar(
          height: 78,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.record_voice_over_rounded), label: 'Talk'),
            NavigationDestination(icon: Icon(Icons.menu_book_rounded), label: 'Book'),
            NavigationDestination(icon: Icon(Icons.language_rounded), label: 'Languages'),
          ],
        ),
      ),
    );
  }
}
