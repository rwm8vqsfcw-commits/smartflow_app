import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:geolocator/geolocator.dart';

// 👇 GLOBALS
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

late WebViewController globalController;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        globalController.loadRequest(
          Uri.parse(response.payload!),
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
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController controller;

  Future<void> requestLocationPermission() async {
    var status = await Permission.location.request();

    if (status.isGranted) {
      print("📍 Location permission granted");
    } else if (status.isDenied) {
      print("❌ Location permission denied");
    } else if (status.isPermanentlyDenied) {
      print("⚠️ Permanently denied");
      openAppSettings();
    }
  }

  Future<Position?> getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      print("Location services OFF");
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      print("Permission permanently denied");
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  @override
  void initState() {
    super.initState();

    requestLocationPermission();

    late final PlatformWebViewControllerCreationParams params;

    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
            onPageFinished: (url) async {
              print("🌐 Page loaded: $url");

              final position = await getUserLocation();

              if (position != null) {
                await controller.runJavaScript("""
      window.__flutterLat = ${position.latitude};
      window.__flutterLng = ${position.longitude};
    """);
              }

              // 🔥 OVERRIDE GEOLOCATION (KEY FIX)
              await controller.runJavaScript("""
    navigator.geolocation.getCurrentPosition = function(success, error) {
        success({
            coords: {
                latitude: window.__flutterLat || 0,
                longitude: window.__flutterLng || 0
            }
        });
    };
  """);

              // keep your token logic
              FirebaseMessaging messaging = FirebaseMessaging.instance;
              String? token = await messaging.getToken();

              if (token != null) {
                await controller.runJavaScript(
                  "localStorage.setItem('fcm_token', '$token');",
                );
              }
            }
        ), // 👈 THIS WAS MISSING
      )
      ..loadRequest(Uri.parse('https://hrm.felicitysolar.ng/login'));
    // 👇 ADD IT HERE (directly below controller creation)
    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;

      androidController.setGeolocationEnabled(true);
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.enableZoom(false);

      androidController.setOnPlatformPermissionRequest(
            (request) {
          request.grant(); // 🔥 THIS is the real fix
        },
      );
    }

    globalController = controller;

    initFirebase();
  }

  Future<void> initFirebase() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission();
    print("🔔 Permission: ${settings.authorizationStatus}");

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("📩 Foreground message: ${message.notification?.title}");

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
        ),
        payload: message.data['url'] ?? "/dashboard",
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WebViewWidget(controller: controller),
    );
  }
}