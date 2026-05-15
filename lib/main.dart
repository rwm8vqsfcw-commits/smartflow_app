import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
InAppWebViewController? globalController; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      if (response.payload != null && globalController != null) {
        globalController!.loadUrl(
          urlRequest: URLRequest(
            url: WebUri(response.payload!),
          ),
        );
      }
    },
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key}); // Added key parameter

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key}); // Added key parameter

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? controller;
  bool _shouldRenderWebView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestLocationPermission();
      initFirebase();
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            _shouldRenderWebView = true;
          });
        }
      });
    });
  }

  Future<void> requestLocationPermission() async {
    var status = await Permission.location.request();
    if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  Future<Position?> getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 5),
    );
  }

  Future<void> initFirebase() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    
    FirebaseMessaging.onMessage.listen(
      (RemoteMessage message) {
        flutterLocalNotificationsPlugin.show(
          0,
          message.notification?.title ?? "Notification",
          message.notification?.body ?? "",
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'default_channel',
              'Default Notifications',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: message.data['url'] ?? "https://felicitysolar.ng",
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: !_shouldRenderWebView
            ? const Center(child: CircularProgressIndicator(color: Colors.blueGrey))
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
                    supportMultipleWindows: true, // FIXED PROPERTY NAME
                    javaScriptCanOpenWindowsAutomatically: true,
                    userAgent: Platform.isIOS
                        ? "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
                        : "Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36",
                  ),
                  onWebViewCreated: (webController) {
                    controller = webController;
                    globalController = webController;
                  },
                  
                  onCreateWindow: (webController, createWindowAction) async {
                    webController.loadUrl(urlRequest: createWindowAction.request);
                    return true;
                  },

                  onReceivedError: (webController, request, error) {
                    if (error.type == WebResourceErrorType.CANCELLED) return;
                  },

                  onConsoleMessage: (webController, consoleMessage) {},

                  onLoadStop: (webController, url) async {
                    await webController.evaluateJavascript(
                      source: """
                        if (typeof window.Notification === 'undefined') {
                          window.Notification = {
                            permission: 'granted',
                            requestPermission: function() {
                              return Promise.resolve('granted');
                            }
                          };
                        }
                      """,
                    );

                    getUserLocation().then((position) async {
                      if (position != null) {
                        await webController.evaluateJavascript(
                          source: """
                            window.__flutterLat = ${position.latitude};
                            window.__flutterLng = ${position.longitude};
                            navigator.geolocation.getCurrentPosition = function(success, error) {
                              success({ coords: { latitude: window.__flutterLat || 0, longitude: window.__flutterLng || 0 } });
                            };
                          """,
                        );
                      }
                    }).catchError((e) {
                      return null; // FIXED RETURN TYPE EXCEPTION
                    });

                    FirebaseMessaging.instance.getToken().then((token) async {
                      if (token != null) {
                        await webController.evaluateJavascript(
                          source: "localStorage.setItem('fcm_token', '$token');",
                        );
                      }
                    });
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.GRANT,
                    );
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    return NavigationActionPolicy.ALLOW;
                  },
                  onDownloadStartRequest: (controller, request) async {},
                ),
              ),
      ),
    );
  }
}
