import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/rs232_echo_page.dart';
import 'pages/gpio_control_page.dart';
import 'pages/nfc_reader_page.dart';
import 'pages/vending_machine_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _enterKioskMode();
  runApp(const MainApp());
}

/// Hides status bar, navigation bar, and keeps them hidden (sticky immersive).
void _enterKioskMode() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-enter immersive mode after NFC dialogs or other interruptions
    if (state == AppLifecycleState.resumed) {
      _enterKioskMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Edge Shop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const VendingMachinePage(),
      routes: {
        '/debug': (_) => const DebugToolsPage(),
      },
    );
  }
}

/// Debug page giving access to the low-level hardware test tools.
class DebugToolsPage extends StatefulWidget {
  const DebugToolsPage({super.key});

  @override
  State<DebugToolsPage> createState() => _DebugToolsPageState();
}

class _DebugToolsPageState extends State<DebugToolsPage> {
  int _currentIndex = 0;

  static const List<Widget> _pages = [
    GpioControlPage(),
    RS232EchoPage(),
    NfcReaderPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Tools'),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.toggle_on_outlined),
            selectedIcon: Icon(Icons.toggle_on),
            label: 'GPIO Control',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal),
            label: 'RS-232 Echo',
          ),
          NavigationDestination(
            icon: Icon(Icons.nfc_outlined),
            selectedIcon: Icon(Icons.nfc),
            label: 'NFC Reader',
          ),
        ],
      ),
    );
  }
}
