import 'package:flutter/material.dart';

import 'pages/survey_home_page.dart';

void main() => runApp(const WiFiFingerprintApp());

class WiFiFingerprintApp extends StatelessWidget {
  const WiFiFingerprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Fingerprint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: const SurveyHomePage(),
    );
  }
}
