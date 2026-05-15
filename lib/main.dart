import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
// Changed from late to nullable to prevent silent crashes
InAppWebViewController? globalController; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  
  // CRITICAL: iOS requires Darwin initialization settings configured explicitly
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
    // Wrap permissions in post frame to avoid breaking UI initialization threads
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
      timeLimit: const Duration(seconds: 5), // Added timeout fallback
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
    return Scaffold( // Removed SafeArea boundary wrapping to avoid zero-height webview errors
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
        ),
        onWebViewCreated: (webController) {
          controller = webController;
          globalController = webController;
        },
        onLoadStop: (webController, url) async {
          // CRITICAL: Removed blocking await. Fetch location asynchronously 
          // so the UI thread doesn't halt and draw a white canvas.
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


          // Token processing
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
