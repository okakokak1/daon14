import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DaonCrmApp());
}

class DaonCrmApp extends StatelessWidget {
  const DaonCrmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '다온시스템 CRM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD32F2F)),
        useMaterial3: true,
      ),
      home: const PermissionWrapper(),
    );
  }
}

class PermissionWrapper extends StatefulWidget {
  const PermissionWrapper({super.key});

  @override
  State<PermissionWrapper> createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> {
  static const _overlayChannel = MethodChannel('com.daonsystem.daon_crm/overlay');

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.phone,
      Permission.notification,
    ].request();

    if (!await Permission.systemAlertWindow.isGranted) {
      await Permission.systemAlertWindow.request();
    }

    try {
      await _overlayChannel.invokeMethod('requestCallerIdRole');
      await _overlayChannel.invokeMethod('startMonitorService');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}