import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const PowerEngApp());
}

class PowerEngApp extends StatelessWidget {
  const PowerEngApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Power Engineering Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.amber,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  // Röle Parametreleri (IEC 60255 Standard Inverse)
  double _faultCurrent = 5000;
  double _pickupCurrent = 400;
  double _tms = 0.2;

  // Gerilim Düşümü Parametreleri
  double _cableLength = 120;
  double _loadCurrent = 63;
  double _cableSection = 16;

  // IEC 60255 Standart Ters Eğri (k=0.14, alpha=0.02)
  double get _tripTime {
    if (_faultCurrent <= _pickupCurrent) return 0.0;
    final m = _faultCurrent / _pickupCurrent;
    final denominator = pow(m, 0.02) - 1.0;
    if (denominator <= 0) return 0.0;
    return _tms * (0.14 / denominator);
  }

  // AG % Gerilim Düşümü Hesabı (3 Faz - Cu: 0.0175 ohm.mm2/m)
  double get _voltageDropPercent {
    final r = (0.0175 * _cableLength) / _cableSection;
    final deltaU = sqrt(3) * _loadCurrent * r * 0.85;
    return (deltaU / 400.0) * 100.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Power Engineering Suite'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: _tabIndex == 0 ? _buildRelayTab() : _buildVoltageDropTab(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.flash_on), label: 'IEC 60255 Röle'),
          NavigationDestination(icon: Icon(Icons.cable), label: 'Gerilim Düşümü'),
        ],
      ),
    );
  }

  Widget _buildRelayTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Açma Süresi (t)', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Text(
                  _tripTime > 0 ? '${_tripTime.toStringAsFixed(3)} sn' : 'Açma Yok (I ≤ Is)',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.amber),
                ),
                Text('(${(_tripTime * 1000).toStringAsFixed(0)} ms)', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSlider('Arıza Akımı I (A)', _faultCurrent, 500, 20000, (v) => setState(() => _faultCurrent = v)),
        _buildSlider('Eşik Akımı Is (A)', _pickupCurrent, 50, 2000, (v) => setState(() => _pickupCurrent = v)),
        _buildSlider('Zaman Çarpanı (TMS)', _tms, 0.05, 1.0, (v) => setState(() => _tms = v)),
      ],
    );
  }

  Widget _buildVoltageDropTab() {
    final isOk = _voltageDropPercent <= 3.0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('% Gerilim Düşümü (e%)', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Text(
                  '%${_voltageDropPercent.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isOk ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
                Text(isOk ? 'Uygun (e% ≤ %3)' : 'Limit Aşıldı!', style: TextStyle(color: isOk ? Colors.green : Colors.red)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSlider('Hat Uzunluğu (m)', _cableLength, 10, 500, (v) => setState(() => _cableLength = v)),
        _buildSlider('Yük Akımı (A)', _loadCurrent, 5, 250, (v) => setState(() => _loadCurrent = v)),
        _buildSlider('Kesit (mm² Cu)', _cableSection, 2.5, 150, (v) => setState(() => _cableSection = v)),
      ],
    );
  }

  Widget _buildSlider(String title, double val, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title: ${val.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        Slider(value: val, min: min, max: max, onChanged: onChanged),
        const SizedBox(height: 8),
      ],
    );
  }
}
