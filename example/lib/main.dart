import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import 'demo/supy_demo_home.dart';

void main() {
  runApp(const SupyScannerExampleApp());
}

class SupyScannerExampleApp extends StatelessWidget {
  const SupyScannerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'supy_scanner example',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6448C3),
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  Future<void> _probeNativeCore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final probe = await SupyScannerChannel.instance.nativeCoreProbe();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'native core ${probe.version} (abi ${probe.abiVersion})',
          ),
        ),
      );
    } on SupyScanError catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('native core unavailable: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Builder(
        builder: (tabContext) => Scaffold(
          appBar: AppBar(
            title: const Text('supy_scanner'),
            actions: [
              Builder(
                builder: (innerContext) => IconButton(
                  tooltip: 'Probe native core (v1.1 debug)',
                  icon: const Icon(Icons.memory),
                  onPressed: () => _probeNativeCore(innerContext),
                ),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Supy Demo', icon: Icon(Icons.auto_awesome)),
                Tab(text: 'Embedded', icon: Icon(Icons.qr_code_scanner)),
                Tab(text: 'Gallery', icon: Icon(Icons.dashboard)),
                Tab(text: 'Batch', icon: Icon(Icons.dynamic_feed)),
                Tab(text: 'Document', icon: Icon(Icons.document_scanner)),
                Tab(text: 'Guidance', icon: Icon(Icons.center_focus_strong)),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              SupyDemoHome(
                onOpenDevTabs: () =>
                    DefaultTabController.of(tabContext).animateTo(1),
              ),
              const _EmbeddedBarcodeTab(),
              const _GalleryTab(),
              const _BatchBarcodeTab(),
              const _DocumentTab(),
              const _DocumentGuidanceTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmbeddedBarcodeTab extends StatefulWidget {
  const _EmbeddedBarcodeTab();

  @override
  State<_EmbeddedBarcodeTab> createState() => _EmbeddedBarcodeTabState();
}

class _EmbeddedBarcodeTabState extends State<_EmbeddedBarcodeTab> {
  final SupyBarcodeScannerController _controller =
      SupyBarcodeScannerController();
  SupyBarcode? _last;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        SupyBarcodeScannerView(
          controller: _controller,
          onBarcodeDetected: (b) => setState(() => _last = b),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'torch',
            onPressed: () async {
              await _controller.setTorch(on: !_torchOn);
              setState(() => _torchOn = !_torchOn);
            },
            child: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ),
        if (_last != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              color: Colors.black.withValues(alpha: 0.78),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${_last!.format.wireName}\n${_last!.rawValue}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// V1-S1_5-13 — Demo gallery showcasing `SupyBarcodeScannerScreen` across
/// every use-case variant + a palette picker (Scanbot Dark / Scanbot Light).
class _GalleryTab extends StatefulWidget {
  const _GalleryTab();

  @override
  State<_GalleryTab> createState() => _GalleryTabState();
}

enum _PaletteChoice { dark, light }

class _GalleryTabState extends State<_GalleryTab> {
  _PaletteChoice _palette = _PaletteChoice.dark;

  SupyScannerPalette get _activePalette => switch (_palette) {
        _PaletteChoice.dark => const SupyScannerPalette.scanbotDark(),
        _PaletteChoice.light => const SupyScannerPalette.scanbotLight(),
      };

  Future<void> _launch(BuildContext context, SupyScanUseCase useCase) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final palette = _activePalette;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => SupyBarcodeScannerScreen(
          useCase: useCase,
          palette: palette,
          onCancel: () => navigator.maybePop(),
          onSingleScan: (b) {
            navigator.maybePop();
            messenger.showSnackBar(
              SnackBar(content: Text('Single: ${b.rawValue}')),
            );
          },
          onMultipleScan: (items) {
            navigator.maybePop();
            messenger.showSnackBar(
              SnackBar(content: Text('Multi: ${items.length} items')),
            );
          },
          onFindAndPick: (rows) {
            navigator.maybePop();
            messenger.showSnackBar(
              SnackBar(content: Text('FindAndPick: ${rows.length} rows')),
            );
          },
          onError: (e) => messenger.showSnackBar(
            SnackBar(content: Text('Error: $e')),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Palette', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<_PaletteChoice>(
          segments: const [
            ButtonSegment(
              value: _PaletteChoice.dark,
              label: Text('Scanbot Dark'),
              icon: Icon(Icons.dark_mode),
            ),
            ButtonSegment(
              value: _PaletteChoice.light,
              label: Text('Scanbot Light'),
              icon: Icon(Icons.light_mode),
            ),
          ],
          selected: {_palette},
          onSelectionChanged: (s) => setState(() => _palette = s.first),
        ),
        const SizedBox(height: 24),
        Text('Use cases', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text('Single scan'),
            subtitle: const Text('Pauses on first detection · confirm sheet'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _launch(context, const SupySingleScanUseCase()),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.bolt),
            title: const Text('Single scan (immediate)'),
            subtitle: const Text('Returns first detection without sheet'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _launch(
              context,
              const SupySingleScanUseCase(
                config: SupySingleScanUseCaseConfiguration(
                  confirmationSheetEnabled: false,
                ),
              ),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.format_list_numbered),
            title: const Text('Multiple scan — counting'),
            subtitle: const Text('Same code increments count'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _launch(
              context,
              const SupyMultipleScanUseCase(
                config: SupyMultipleScanUseCaseConfiguration(
                  mode: SupyMultipleScanMode.counting,
                ),
              ),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Multiple scan — unique'),
            subtitle: const Text('Deduplicates by raw value'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _launch(
              context,
              const SupyMultipleScanUseCase(
                config: SupyMultipleScanUseCaseConfiguration(
                  mode: SupyMultipleScanMode.unique,
                ),
              ),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.checklist),
            title: const Text('Find and pick'),
            subtitle: const Text('Pick-list with per-row progress'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _launch(
              context,
              const SupyFindAndPickUseCase(
                config: SupyFindAndPickUseCaseConfiguration(
                  expected: [
                    SupyExpectedBarcode(
                      rawValue: '1234567890123',
                      expectedCount: 2,
                      label: 'Sample EAN-13',
                    ),
                    SupyExpectedBarcode(
                      rawValue: '9876543210',
                      expectedCount: 1,
                      label: 'Sample UPC',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BatchBarcodeTab extends StatefulWidget {
  const _BatchBarcodeTab();

  @override
  State<_BatchBarcodeTab> createState() => _BatchBarcodeTabState();
}

class _BatchBarcodeTabState extends State<_BatchBarcodeTab> {
  SupyBatchBarcodeResult? _result;
  String? _error;
  bool _running = false;

  Future<void> _scan({int maxBatchCount = 0}) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await SupyScannerChannel.instance.scanBarcodesBatch(
        SupyBatchBarcodeScanOptions(
          maxBatchCount: maxBatchCount,
        ),
      );
      setState(() => _result = result);
    } on SupyScanError catch (e) {
      if (e.code == SupyScanErrorCode.cancelled) {
        // Cancelling is a normal path — don't render as an error.
        setState(() {});
      } else {
        setState(() => _error = '${e.code.name}: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _result?.items ?? const <SupyBarcode>[];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : () => _scan(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Unlimited'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _running ? null : () => _scan(maxBatchCount: 5),
                  icon: const Icon(Icons.numbers),
                  label: const Text('Cap at 5'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_result != null)
            Text(
              'Unique: ${items.length}  ·  Duplicates suppressed: '
              '${_result!.duplicateCount}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'Tap a button above to start a batch session.\n'
                      'Same code re-scanned within 800ms is dropped.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = items[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(b.rawValue),
                        subtitle: Text(b.format.wireName),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTab extends StatefulWidget {
  const _DocumentTab();

  @override
  State<_DocumentTab> createState() => _DocumentTabState();
}

class _DocumentTabState extends State<_DocumentTab> {
  SupyDocumentData? _result;
  String? _error;
  bool _running = false;

  Future<void> _scan({int maxPages = 0}) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await SupyScannerChannel.instance.scanDocument(
        SupyDocumentScanOptions(maxPages: maxPages),
      );
      setState(() => _result = result);
    } on SupyScanError catch (e) {
      if (e.code == SupyScanErrorCode.cancelled) {
        setState(() {});
      } else {
        setState(() => _error = '${e.code.name}: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _result?.pages ?? const <SupyDocumentPage>[];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : () => _scan(),
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('Scan (no limit)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _running ? null : () => _scan(maxPages: 3),
                  icon: const Icon(Icons.filter_3),
                  label: const Text('Max 3 pages'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_result != null)
            Text(
              'Pages: ${pages.length}  ·  OCR chars: ${_result!.ocrText.length}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: pages.isEmpty
                ? const Center(child: Text('No scan yet.'))
                : ListView(
                    children: [
                      SizedBox(
                        height: 180,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: pages.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final page = pages[i];
                            final file = File(Uri.parse(page.uri).toFilePath());
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: file.existsSync()
                                  ? Image.file(file, fit: BoxFit.cover)
                                  : Container(
                                      width: 120,
                                      color: Colors.grey.shade300,
                                      alignment: Alignment.center,
                                      child: Text('Page ${i + 1}'),
                                    ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_result!.ocrText.isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_result!.ocrText),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Demonstrates the embedded `SupyDocumentScannerView` with live edge guidance.
/// Shows the green/red outline + hint copy driven by the state machine, and
/// fires a snackbar the first time the document is deemed `ready` (auto-snap
/// target — capture/OCR wiring lands downstream of this prototype).
class _DocumentGuidanceTab extends StatefulWidget {
  const _DocumentGuidanceTab();

  @override
  State<_DocumentGuidanceTab> createState() => _DocumentGuidanceTabState();
}

class _DocumentGuidanceTabState extends State<_DocumentGuidanceTab> {
  final SupyDocumentScannerController _controller =
      SupyDocumentScannerController();
  SupyDocumentFrameState _state = SupyDocumentFrameState.noDocument;
  bool _torchOn = false;
  bool _flashAvailable = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onReady(SupyDocumentGuidanceFrame frame) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Document ready — capture would fire here.'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        SupyDocumentScannerView(
          controller: _controller,
          onGuidance: (frame) {
            if (frame.state != _state) {
              setState(() => _state = frame.state);
            }
          },
          onReady: _onReady,
          onPreviewStarted: (flashAvailable) =>
              setState(() => _flashAvailable = flashAvailable),
        ),
        if (_flashAvailable)
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'doc-torch',
              onPressed: () async {
                await _controller.setTorch(on: !_torchOn);
                setState(() => _torchOn = !_torchOn);
              },
              child: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            ),
          ),
        Positioned(
          top: 16,
          left: 16,
          child: Card(
            color: Colors.black.withValues(alpha: 0.55),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              child: Text(
                'state: ${_state.name}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
