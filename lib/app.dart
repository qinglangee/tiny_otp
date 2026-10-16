import 'package:flutter/material.dart';

import 'features/accounts/accounts_page.dart';

class TinyOtpApp extends StatelessWidget {
  const TinyOtpApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF315C9B);
    return MaterialApp(
      title: 'TinyOTP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true),
      home: const AccountsPage(),
    );
  }
}
