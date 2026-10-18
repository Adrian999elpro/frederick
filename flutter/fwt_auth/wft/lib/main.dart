import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'portal_policy.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const FrederickApp()); }
class FrederickApp extends StatelessWidget {
  const FrederickApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'Frederick Escolar', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffb52b36))), home: const SchoolPortal());
}
class SchoolPortal extends StatefulWidget {
  const SchoolPortal({super.key});
  @override
  State<SchoolPortal> createState() => _SchoolPortalState();
}
class _SchoolPortalState extends State<SchoolPortal> {
  static const _nfc = MethodChannel('ec.frederick.escolar/nfc');
  late final WebViewController _web;
  int _progress = 0;
  bool _failed = false, _scanning = false;
  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xff0b0e14))
      ..addJavaScriptChannel('FrederickNfc', onMessageReceived: (message) async {
        final current = await _web.currentUrl();
        if (current == null || !allowedPortalUrl(current) || message.message != 'scan') return;
        await _scan();
      })
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) => allowedPortalUrl(request.url) ? NavigationDecision.navigate : NavigationDecision.prevent,
        onProgress: (value) { if (mounted) setState(() => _progress = value); },
        onPageStarted: (_) { if (mounted) setState(() => _failed = false); },
        onWebResourceError: (error) { if (error.isForMainFrame == true && mounted) setState(() => _failed = true); },
      ))
      ..loadRequest(Uri.parse(portalUrl));
    final platform = _web.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnShowFileSelector((params) async {
        try {
          final photo = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 90);
          return photo == null ? <String>[] : [Uri.file(photo.path).toString()];
        } catch (_) { return <String>[]; }
      });
    }
  }
  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    String? uid, error;
    try { uid = await _nfc.invokeMethod<String>('scan'); }
    on PlatformException catch (e) { error = e.message ?? 'No se pudo leer la tarjeta.'; }
    finally { if (mounted) setState(() => _scanning = false); }
    final current = await _web.currentUrl();
    if (current != null && allowedPortalUrl(current)) {
      await _web.runJavaScript('window.dispatchEvent(new CustomEvent("frederick-nfc", {detail: ${jsonEncode({'uid': uid, 'error': error})}}));');
    }
  }
  Future<void> _back() async { if (await _web.canGoBack()) { await _web.goBack(); } else { await SystemNavigator.pop(); } }
  @override
  void dispose() { _nfc.invokeMethod<void>('cancel'); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(canPop: false, onPopInvokedWithResult: (didPop, result) { if (!didPop) _back(); },
    child: Scaffold(body: SafeArea(child: Column(children: [
      if (_progress < 100 && !_failed) LinearProgressIndicator(value: _progress / 100),
      if (_scanning) Material(color: const Color(0xfff7e2ad), child: ListTile(leading: const Icon(Icons.nfc), title: const Text('Acerca tu tarjeta al teléfono'), trailing: TextButton(onPressed: () => _nfc.invokeMethod<void>('cancel'), child: const Text('Cancelar')))),
      Expanded(child: _failed ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off, size: 48), const SizedBox(height: 16), const Text('No se pudo conectar con Frederick. Revisa tu conexión a internet.', textAlign: TextAlign.center),
        const SizedBox(height: 16), FilledButton(onPressed: () { setState(() => _failed = false); _web.reload(); }, child: const Text('Reintentar')),
      ]))) : WebViewWidget(controller: _web)),
    ]))));
}
