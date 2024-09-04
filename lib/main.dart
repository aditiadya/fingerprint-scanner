import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:object_detection/crop.dart';




void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
    apiKey: "AIzaSyC38Ft9VwSRcIK45vkmW0M1HL0L2RC4DQY",
    authDomain: "fingerprint-6cf3d.firebaseapp.com",
    projectId: "fingerprint-6cf3d",
    storageBucket: "fingerprint-6cf3d.appspot.com",
    messagingSenderId: "296122770833",
    appId: "1:296122770833:web:9d014cbde022f3ee672630",
    measurementId: "G-VWFLM0BBBS"
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OBJECT DETECTOR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        
        primarySwatch: Colors.blue,
      ),
      home: const CropScreen(),
    );
  }
}

