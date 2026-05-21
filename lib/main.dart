import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

  bool notificationsEnabled = false;

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
            setState(() {
              isLoading = false;
            });
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

        floatingActionButton:

        notificationsEnabled
            ? null
            : FloatingActionButton.extended(

          onPressed: () {

            showDialog(
              context: context,
              builder: (context) {

                return AlertDialog(
                  title: Text(
                    "Enable Notifications",
                  ),

                  content: Text(
                    "Allow Smartflow App to send you notifications for approvals, attendance updates and HR alerts.",
                  ),

                  actions: [

                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: Text("Cancel"),
                    ),

                    ElevatedButton(
                      onPressed: () async {

                        Navigator.pop(context);

                        try {

                          await Firebase.initializeApp();

                          FirebaseMessaging messaging =
                              FirebaseMessaging.instance;

                          NotificationSettings settings =
                          await messaging.requestPermission(
                            alert: true,
                            badge: true,
                            sound: true,
                          );

                          if (
                          settings.authorizationStatus ==
                              AuthorizationStatus.authorized
                          ) {

                            String? token =
                            await messaging.getToken();

                            print("FCM TOKEN: $token");

                            if (token != null) {

                              await controller.runJavaScript(
                                  """
                          localStorage.setItem(
                            'fcm_token',
                            '$token'
                          );
                          """
                              );

                              await controller.runJavaScript(
                                  """
                          fetch('/save-device-token', {
                            method: 'POST',
                            headers: {
                              'Content-Type': 'application/json',
                              'X-CSRF-TOKEN':
                                document.querySelector(
                                  'meta[name="csrf-token"]'
                                ).content
                            },
                            body: JSON.stringify({
                              token: '$token',
                              device: 'ios_app'
                            })
                          });
                          """
                              );

                              setState(() {
                                notificationsEnabled = true;
                              });

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Notifications enabled successfully.",
                                  ),
                                ),
                              );
                            }

                          }

                        } catch (e) {

                          print(e);

                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(
                                "Notification setup failed.",
                              ),
                            ),
                          );

                        }

                      },
                      child: Text("Enable"),
                    ),

                  ],
                );

              },
            );

          },

          icon: Icon(Icons.notifications_active),

          label: Text("Notifications"),
        ),

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