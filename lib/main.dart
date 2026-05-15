import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  // Bypassed all asynchronous services to guarantee runApp() executes instantly
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? controller;
  bool _shouldRenderWebView = false;

  @override
  void initState() {
    super.initState();
    // Short layout delay to prevent iOS transparency rendering bugs
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _shouldRenderWebView = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey, 
      body: !_shouldRenderWebView
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            )
          : SizedBox.expand(
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri("https://felicitysolar.ng"),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  useShouldOverrideUrlLoading: true,
                  allowFileAccessFromFileURLs: true,
                  allowUniversalAccessFromFileURLs: true,
                  allowsInlineMediaPlayback: true,
                  useOnDownloadStart: true,
                  userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
                ),
                onWebViewCreated: (webController) {
                  controller = webController;
                },
                onReceivedError: (webController, request, error) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("WebView Network Error"),
                      content: Text("Code: ${error.type}\n\nMessage: ${error.description}"),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
