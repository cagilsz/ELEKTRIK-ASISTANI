// Konum: lib/main.dart

import 'package:flutter/material.dart';
import 'screens/main_cockpit.dart'; // Arayüz dosyamızı çağırıyoruz

void main() {
  runApp(const PowerFieldProApp());
}

class PowerFieldProApp extends StatelessWidget {
  const PowerFieldProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerField Pro v6.8',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF070A0E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB300),
          secondary: Color(0xFF00E676),
          error: Color(0xFFFF3D00),
          surface: Color(0xFF111622),
        ),
      ),
      home: const MainCockpit(), // Uygulama Kokpit ekranından başlıyor
    );
  }
}
