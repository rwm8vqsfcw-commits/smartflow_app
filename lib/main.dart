import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

late InAppWebViewController globalController;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse:
        (NotificationResponse response) async {
      if (response.payload != null) {
        globalController.loadUrl(
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

    requestLocationPermission();

    initFirebase();
  }

  Future<void> requestLocationPermission() async {
    var status = await Permission.location.request();

    if (status.isPermanentlyDenied) {
      openAppSettings();
    }
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
          ),
          payload: message.data['url'] ??
              "https://hrm.felicitysolar.ng/dashboard",
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(
              "https://hrm.felicitysolar.ng/login",
            ),
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
            final position = await getUserLocation();

            if (position != null) {
              await webController.evaluateJavascript(
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

            FirebaseMessaging messaging =
                FirebaseMessaging.instance;

            String? token = await messaging.getToken();

            if (token != null) {
              await webController.evaluateJavascript(
                source:
                    "localStorage.setItem('fcm_token', '$token');",
              );
            }
          },

          onPermissionRequest:
              (controller, request) async {
            return PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.GRANT,
            );
          },

          shouldOverrideUrlLoading:
              (controller, navigationAction) async {
            return NavigationActionPolicy.ALLOW;
          },

          onDownloadStartRequest:
              (controller, request) async {
            print("Downloading: ${request.url}");
          },
        ),
      ),
    );
  }
}