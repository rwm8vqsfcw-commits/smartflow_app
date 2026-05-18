import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
//import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();



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
        // notification click
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

  bool isLoading = true;
  bool hasError = false;
  String errorMessage = "";

  WebViewController? controller;

  @override
  void initState() {
    super.initState();

    requestLocationPermission();

    // initFirebase();
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

/*
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
  */


  @override
  Widget build(BuildContext context) {
    controller ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(

        NavigationDelegate(

          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
            });
          },

          onPageFinished: (String url) async {
            setState(() {
              isLoading = false;
            });

            final position = await getUserLocation();

            if (position != null) {
              controller?.runJavaScript(
                """
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
          },

          onWebResourceError: (error) {
            setState(() {
              hasError = true;
              errorMessage = error.description;
            });
          },

          onNavigationRequest: (NavigationRequest request) async {
            final url = request.url;

            if (
            url.toLowerCase().endsWith(".pdf") ||
                url.toLowerCase().endsWith(".doc") ||
                url.toLowerCase().endsWith(".docx") ||
                url.toLowerCase().endsWith(".xls") ||
                url.toLowerCase().endsWith(".xlsx") ||
                url.contains("/storage/")
            ) {
              await launchUrl(
                Uri.parse(url),
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

    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [

            WebViewWidget(
              controller: controller!,
            ),

            if (hasError)
              Container(
                color: Colors.white,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      errorMessage,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
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