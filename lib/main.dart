import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

final FlutterLocalNotificationsPlugin
flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  if (Platform.isAndroid) {

    const AndroidInitializationSettings
    androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings
    initializationSettings =
    InitializationSettings(
      android: androidSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
    );

  }

  if (Platform.isIOS) {

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

  }

  FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) async {

      if (message.notification != null) {

        await flutterLocalNotificationsPlugin.show(
          0,
          message.notification!.title,
          message.notification!.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'smartflow_channel',
              'Smartflow Notifications',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );

      }

    },
  );

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

  InAppWebViewController? controller;

  bool isLoading = true;

  bool androidTokenRegistered = false;

  Future<void> requestLocationPermission() async {

    await Permission.location.request();

  }

  Future<Position?> getUserLocation() async {

    bool serviceEnabled =
    await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return null;
    }

    LocationPermission permission =
    await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

  }

  void handleNotificationNavigation(
      RemoteMessage message
      ) {

    final url = message.data['url'];

    if (
    url != null &&
        url.toString().isNotEmpty
    ) {

      Future.delayed(
        Duration(seconds: 1),
            () {

          controller?.loadUrl(
            urlRequest: URLRequest(
              url: WebUri(url),
            ),
          );

        },
      );

    }

  }

  Future<void> autoRegisterAndroidToken() async {

    try {

      FirebaseMessaging messaging =
          FirebaseMessaging.instance;

      await messaging.requestPermission();

      String? token =
      await messaging.getToken();

      print("ANDROID TOKEN: $token");

      if (token != null) {

        await Future.delayed(
          Duration(seconds: 3),
        );

        final userIdResult =
        await controller?.evaluateJavascript(
          source:
          "localStorage.getItem('logged_user_id');",
        );

        String userId =
        userIdResult.toString().replaceAll('"', '');

        if (
        userId.isNotEmpty &&
            userId != 'null'
        ) {

          final response = await http.get(
            Uri.parse(
                "https://hrm.felicitysolar.ng/save-device-token-app/$userId/${Uri.encodeComponent(token)}/android_app"
            ),
          );

          print("ANDROID SAVE: ${response.body}");

          setState(() {
            notificationsEnabled = true;
          });

          await controller?.evaluateJavascript(
            source:
            "localStorage.setItem('notifications_enabled', '1');",
          );

        }

      }

    } catch (e) {

      print("ANDROID TOKEN ERROR: $e");

    }

  }

  @override
  void initState() {
    super.initState();

    if (Platform.isAndroid) {
      requestLocationPermission();
    }

    FirebaseMessaging.onMessageOpenedApp.listen(
      handleNotificationNavigation,
    );

    FirebaseMessaging.instance
        .getInitialMessage()
        .then((message) {

      if (message != null) {

        handleNotificationNavigation(message);

      }

    });
  }

  @override
  Widget build(BuildContext context) {

    return SafeArea(
      child: Scaffold(

        floatingActionButton:

        Platform.isAndroid
            ? null
            : notificationsEnabled
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

                          FirebaseMessaging messaging =
                              FirebaseMessaging.instance;

                          NotificationSettings settings =
                          await messaging.requestPermission(
                            alert: true,
                            badge: true,
                            sound: true,
                          );

                          if (Platform.isIOS) {

                            String? apnsToken;

                            for (int i = 0; i < 10; i++) {

                              apnsToken =
                              await messaging.getAPNSToken();

                              if (apnsToken != null) {
                                break;
                              }

                              await Future.delayed(
                                Duration(seconds: 1),
                              );

                            }

                          }

                          if (
                          settings.authorizationStatus ==
                              AuthorizationStatus.authorized
                          ) {

                            String? token =
                            await messaging.getToken();

                            if (token != null) {

                              await controller?.evaluateJavascript(
                                source:
                                """
                                localStorage.setItem(
                                  'fcm_token',
                                  '$token'
                                );
                                """,
                              );

                              final userIdResult =
                              await controller?.evaluateJavascript(
                                source:
                                "localStorage.getItem('logged_user_id');",
                              );

                              String userId =
                              userIdResult.toString()
                                  .replaceAll('"', '');

                              final response = await http.get(
                                Uri.parse(
                                    "https://hrm.felicitysolar.ng/save-device-token-app/$userId/${Uri.encodeComponent(token)}/ios_app"
                                ),
                              );

                              print(
                                  "TOKEN SAVE STATUS: ${response.statusCode}"
                              );

                              print(
                                  "TOKEN SAVE BODY: ${response.body}"
                              );

                              setState(() {
                                notificationsEnabled = true;
                              });

                              await controller?.evaluateJavascript(
                                source:
                                "localStorage.setItem('notifications_enabled', '1');",
                              );

                            }

                          }

                        } catch (e) {

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "ERROR: $e",
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

            InAppWebView(

              initialUrlRequest: URLRequest(
                url: WebUri(
                  "https://hrm.felicitysolar.ng/login",
                ),
              ),

              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                geolocationEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useShouldOverrideUrlLoading: true,
              ),

              onWebViewCreated:
                  (InAppWebViewController webViewController) {

                controller = webViewController;

              },

              onLoadStart: (controller, url) {

                setState(() {
                  isLoading = true;
                });

              },

              onLoadStop:
                  (controller, url) async {

                setState(() {
                  isLoading = false;
                });

                final position = await getUserLocation();

                if (position != null) {

                  await controller.evaluateJavascript(
                    source: """
                      window.__flutterLat = ${position.latitude};
                      window.__flutterLng = ${position.longitude};
                
                      navigator.geolocation.getCurrentPosition =
                      function(success, error) {
                        success({
                          coords: {
                            latitude: window.__flutterLat || 0,
                            longitude: window.__flutterLng || 0
                          }
                        });
                      };
                    """,
                  );

                }

                if (
                Platform.isAndroid &&
                    !androidTokenRegistered
                ) {

                  final userIdResult =
                  await controller.evaluateJavascript(
                    source:
                    "localStorage.getItem('logged_user_id');",
                  );

                  String userId =
                  userIdResult.toString().replaceAll('"', '');

                  if (
                  userId.isNotEmpty &&
                      userId != 'null'
                  ) {

                    androidTokenRegistered = true;

                    await autoRegisterAndroidToken();

                  }

                }

                final enabledResult =
                await controller.evaluateJavascript(
                  source:
                  "localStorage.getItem('notifications_enabled');",
                );

                if (
                enabledResult.toString()
                    .replaceAll('"', '') ==
                    '1'
                ) {

                  setState(() {
                    notificationsEnabled = true;
                  });

                }

              },

              shouldOverrideUrlLoading:
                  (controller, navigationAction) async {

                final url =
                navigationAction.request.url.toString();

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
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );

                  return NavigationActionPolicy.CANCEL;

                }

                return NavigationActionPolicy.ALLOW;

              },
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