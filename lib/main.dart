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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestLocationPermission();
      initFirebase();
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
          payload: message.data['url'] ?? "https://hrm.felicitysolar.ng/dashboard",
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri("https://hrm.felicitysolar.ng/login"),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          useShouldOverrideUrlLoading: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          allowsInlineMediaPlayback: true,
          useOnDownloadStart: true,
          // CRITICAL FIX: Forces the WebView container to impersonate standard iOS Safari mobile
          userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
        ),
        onWebViewCreated: (webController) {
          controller = webController;
          globalController = webController;
        },
        
        // 1. DIAGNOSTIC: Captures native iOS network stack/security failures
        onReceivedError: (webController, request, error) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (context) => AlertDialog(
              title: const Text("WebView Network Error"),
              content: Text("Code: ${error.type}\n\nMessage: ${error.description}\n\nURL: ${request.url}"),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Dismiss"))],
            ),
          );
        },

        // 2. DIAGNOSTIC: Captures JavaScript run-time execution crashes on screen
        onConsoleMessage: (webController, consoleMessage) {
          if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR) {
            showDialog(
              context: context,
              barrierDismissible: true,
              builder: (context) => AlertDialog(
                title: const Text("JS Console Error"),
                content: Text(consoleMessage.message),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Dismiss"))],
              ),
            );
          }
        },

        onLoadStop: (webController, url) async {
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
            print("Location error: \$e");
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
        onDownloadStartRequest: (controller, request) async {
          print("Downloading: ${request.url}");
        },
      ),
    );
  }
}
