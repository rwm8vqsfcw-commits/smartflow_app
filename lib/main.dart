import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() =>
      _WebViewScreenState();
}

class _WebViewScreenState
    extends State<WebViewScreen> {

  late final WebViewController controller;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..setNavigationDelegate(
        NavigationDelegate(

          onPageStarted: (url) {
            setState(() {
              isLoading = true;
            });
          },

          onPageFinished: (url) {

            controller.runJavaScript(
                """
              var buttons = document.querySelectorAll('*');

              buttons.forEach(function(btn) {
                if (
                  btn.innerText &&
                  btn.innerText.toLowerCase().includes('enable notifications')
                ) {
                  btn.style.display = 'none';
                }
              });
              """
            );

            setState(() {
              isLoading = false;
            });
          },

          onNavigationRequest:
              (NavigationRequest request) async {

            final url = request.url.toLowerCase();

            if (
            url.contains('.pdf') ||
                url.contains('.doc') ||
                url.contains('.docx') ||
                url.contains('.xls') ||
                url.contains('.xlsx') ||
                url.contains('/storage/') ||
                url.contains('/download/')
            ) {

              await launchUrl(
                Uri.parse(request.url),
                mode: LaunchMode.externalApplication,
              );

              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },

        ),
      )
      ..loadRequest(
        Uri.parse(
          "https://hrm.felicitysolar.ng/login",
        ),
      );
  }

  @override
  Widget build(BuildContext context) {

    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [

            WebViewWidget(
              controller: controller,
            ),

            if (isLoading)
              Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    children: [

                      Image.asset(
                        'assets/icon.png',
                        width: 120,
                      ),

                      SizedBox(height: 20),

                      CircularProgressIndicator(),

                      SizedBox(height: 15),

                      Text(
                        "Loading Smartflow...",
                      ),

                    ],
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }
}