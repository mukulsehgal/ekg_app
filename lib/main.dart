import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

/// ====== SET YOUR API URL HERE ======
/// Use your deployed HTTPS API for release builds:
const String API_URL = 'https://your-real-host/api/ekg/interpret';
// For local testing only (comment the HTTPS line above and uncomment this):
// const String API_URL = 'http://192.168.1.122:3000/api/ekg/interpret';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EKG Interpreter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.purple),
      home: const EkgPage(),
    );
  }
}

class EkgPage extends StatefulWidget {
  const EkgPage({super.key});
  @override
  State<EkgPage> createState() => _EkgPageState();
}

class _EkgPageState extends State<EkgPage> with TickerProviderStateMixin {
  final _picker = ImagePicker();
  File? _image;

  // Clinical context
  final _ageCtrl = TextEditingController();
  String _sex = 'unspecified';
  final _symptomsCtrl = TextEditingController();
  final _historyCtrl = TextEditingController();
  final _medsCtrl = TextEditingController();
  final _vitalsCtrl = TextEditingController();

  bool _busy = false;
  String _resultRaw = '';
  Map<String, dynamic>? _resultJson;

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _ageCtrl.dispose();
    _symptomsCtrl.dispose();
    _historyCtrl.dispose();
    _medsCtrl.dispose();
    _vitalsCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final x = await _picker.pickImage(source: src); // keep original quality
    if (x != null) setState(() => _image = File(x.path));
  }

  Future<void> _interpret() async {
    if (_image == null) {
      setState(() {
        _resultRaw = 'Please select an EKG image first.';
        _resultJson = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _resultRaw = 'Uploading…';
      _resultJson = null;
    });

    try {
      final req = http.MultipartRequest('POST', Uri.parse(API_URL))
        ..files.add(await http.MultipartFile.fromPath('image', _image!.path));

      // Optional context fields
      if (_ageCtrl.text.trim().isNotEmpty) req.fields['age'] = _ageCtrl.text.trim();
      if (_sex != 'unspecified') req.fields['sex'] = _sex;
      if (_symptomsCtrl.text.trim().isNotEmpty) req.fields['symptoms'] = _symptomsCtrl.text.trim();
      if (_historyCtrl.text.trim().isNotEmpty) req.fields['history'] = _historyCtrl.text.trim();
      if (_medsCtrl.text.trim().isNotEmpty) req.fields['meds'] = _medsCtrl.text.trim();
      if (_vitalsCtrl.text.trim().isNotEmpty) req.fields['vitals'] = _vitalsCtrl.text.trim();

      // You can experiment with server-side modes: 'raw' | 'enh' | 'both'
      // req.fields['mode'] = 'both';

      // Send with a timeout so UI doesn’t hang forever
req.fields['mode'] = 'raw';
      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final body = await streamed.stream.bytesToString();

      String pretty = body;
      Map<String, dynamic>? parsed;

      try {
        parsed = jsonDecode(body) as Map<String, dynamic>;
        pretty = const JsonEncoder.withIndent('  ').convert(parsed);
      } catch (_) {
        // not JSON; leave as raw string
      }

      setState(() {
        _resultRaw = 'HTTP ${streamed.statusCode}\n$pretty';
        _resultJson = parsed;
      });
    } on TimeoutException {
      setState(() {
        _resultRaw = 'Error: Server timed out (60s). Check API_URL / network.';
        _resultJson = null;
      });
    } catch (e) {
      setState(() {
        _resultRaw = 'Error: $e';
        _resultJson = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label.isEmpty ? null : label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      );

  // -------- UI Helpers --------
  Widget _kv(String k, String? v) {
    return Row(
      children: [
        Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text(v ?? '—'),
      ],
    );
  }

  String? _num(dynamic v) => (v == null) ? null : '$v';

  Widget _chipList(List<dynamic>? xs) {
    final items = (xs ?? []).cast<String>();
    if (items.isEmpty) return const Text('—');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((s) => Chip(label: Text(s))).toList(),
    );
  }

  Widget _summary(Map<String, dynamic> j) {
    final intervals = (j['intervals_ms'] ?? {}) as Map<String, dynamic>;
    final ischemia = (j['ischemia'] ?? {}) as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick headline
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _kv('Image quality', j['image_quality'] as String?),
                const SizedBox(height: 6),
                _kv('Rate (bpm)', _num(j['rate_bpm'])),
                const SizedBox(height: 6),
                _kv('Rhythm', j['rhythm'] as String?),
                const Divider(height: 18),
                _kv('Axis (deg)', _num(j['axis_deg'])),
                const SizedBox(height: 6),
                _kv(
                  'Conduction',
                  (j['conduction'] is List && (j['conduction'] as List).isNotEmpty)
                      ? (j['conduction'] as List).join(', ')
                      : '—',
                ),
              ],
            ),
          ),
        ),

        // Intervals
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Intervals (ms)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _kv('PR', _num(intervals['PR'])),
                const SizedBox(height: 6),
                _kv('QRS', _num(intervals['QRS'])),
                const SizedBox(height: 6),
                _kv('QT', _num(intervals['QT'])),
                const SizedBox(height: 6),
                _kv('QTc', _num(intervals['QTc'])),
              ],
            ),
          ),
        ),

        // Ischemia
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ischemia', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('ST Elevation'),
                _chipList((ischemia['st_elev'] as List?)?.cast<String>()),
                const SizedBox(height: 8),
                const Text('ST Depression'),
                _chipList((ischemia['st_depr'] as List?)?.cast<String>()),
                const SizedBox(height: 8),
                const Text('T-wave Inversion'),
                _chipList((ischemia['t_inv'] as List?)?.cast<String>()),
              ],
            ),
          ),
        ),

        // Impression
        if (j['overall_impression'] != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall impression', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(j['overall_impression'] as String),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _copyJson() async {
    final text = _resultJson != null
        ? const JsonEncoder.withIndent('  ').convert(_resultJson)
        : _resultRaw;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    }
  }

  Future<void> _shareJson() async {
    final text = _resultJson != null
        ? const JsonEncoder.withIndent('  ').convert(_resultJson)
        : _resultRaw;
    await Share.share(text, subject: 'EKG Interpretation');
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _image != null;

    return Scaffold(
      appBar: AppBar(title: const Text('EKG Interpreter')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (hasImage)
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_image!, fit: BoxFit.contain),
                ),
              )
            else
              Container(
                height: 220,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('No image selected'),
              ),
            const SizedBox(height: 12),

            // Image actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Take Photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Clinical context fields
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Clinical context (optional)',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ageCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _dec('Age', hint: 'e.g. 58'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _sex,
                    items: const [
                      DropdownMenuItem(value: 'unspecified', child: Text('Sex (optional)')),
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _sex = v ?? 'unspecified'),
                    decoration: _dec(''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _symptomsCtrl,
              maxLines: 2,
              decoration: _dec('Symptoms', hint: 'e.g. chest pain, SOB'),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _historyCtrl,
              maxLines: 2,
              decoration: _dec('History', hint: 'e.g. CAD, HTN, prior MI'),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _medsCtrl,
              maxLines: 2,
              decoration: _dec('Medications', hint: 'e.g. beta-blocker, digoxin'),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _vitalsCtrl,
              maxLines: 2,
              decoration: _dec('Vitals', hint: 'e.g. HR 110, BP 90/60'),
            ),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _busy || !hasImage ? null : _interpret,
              icon: const Icon(Icons.analytics),
              label: Text(_busy ? 'Interpreting…' : 'Interpret EKG'),
            ),

            const SizedBox(height: 16),

            // Actions: Copy / Share
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_resultRaw.isEmpty && _resultJson == null) ? null : _copyJson,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy JSON'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_resultRaw.isEmpty && _resultJson == null) ? null : _shareJson,
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Tabs: Summary / Raw JSON
            TabBar(
              controller: _tab,
              labelColor: Theme.of(context).colorScheme.primary,
              tabs: const [Tab(text: 'Summary'), Tab(text: 'Raw JSON')],
            ),
            const SizedBox(height: 8),

            SizedBox(
              height: 600, // room to scroll
              child: TabBarView(
                controller: _tab,
                children: [
                  // Summary
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 8),
                    child: _resultJson == null
                        ? const Text('No parsed JSON available yet.')
                        : _summary(_resultJson!),
                  ),
                  // Raw
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _resultRaw,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
