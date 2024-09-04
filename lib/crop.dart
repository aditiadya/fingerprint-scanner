import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/rendering.dart';
import 'package:flutter_pytorch/pigeon.dart';
import 'package:flutter_pytorch/flutter_pytorch.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CropScreen extends StatefulWidget {
  const CropScreen({super.key});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late ModelObjectDetection _objectModel;
  List<ResultObjectDetection?> objDetect = [];
  File? _image;
  List<img.Image> croppedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool isProcessing = false;
  bool showCroppedImages = false;

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  Future<void> loadModel() async {
    String pathObjectDetectionModel = "assets/models/best.torchscript.ptl";
    try {
      _objectModel = await FlutterPytorch.loadObjectDetectionModel(
        pathObjectDetectionModel,
        1,
        640,
        640,
        labelPath: "assets/labels/mylabels.txt",
      );
    } catch (e) {
      if (e is PlatformException) {
        print("only supported for android, Error is $e");
      } else {
        print("Error is $e");
      }
    }
  }

  Future<void> runObjectDetection() async {
    setState(() {
      isProcessing = true;
      showCroppedImages = false;
    });

    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) {
      setState(() {
        isProcessing = false;
      });
      return;
    }

    File imageFile = File(image.path);
    Uint8List imageData = await imageFile.readAsBytes();

    img.Image? originalImage = img.decodeImage(imageData);
    if (originalImage == null) {
      print("Error decoding image.");
      setState(() {
        isProcessing = false;
      });
      return;
    }

    objDetect = await _objectModel.getImagePrediction(
      imageData,
      minimumScore: 0.04,
      IOUThershold: 0.3,
    );

    setState(() {
      _image = imageFile;
      isProcessing = false;
    });
  }

  Future<void> _cropImages() async {
    if (_image == null || objDetect.isEmpty) return;

    Uint8List imageData = _image!.readAsBytesSync();
    img.Image? originalImage = img.decodeImage(imageData);

    if (originalImage == null) {
      print("Error decoding image.");
      return;
    }

    croppedImages.clear();
    List<Future<void>> cropFutures = [];

    for (var detection in objDetect) {
      if (detection == null) continue;

      cropFutures.add(Future(() {
        int x = (detection.rect.left * originalImage.width).toInt();
        int y = (detection.rect.top * originalImage.height).toInt();
        int width = (detection.rect.width * originalImage.width).toInt();
        int height = (detection.rect.height * originalImage.height).toInt();

        x = x.clamp(0, originalImage.width - 1);
        y = y.clamp(0, originalImage.height - 1);
        width = width.clamp(1, originalImage.width - x);
        height = height.clamp(1, originalImage.height - y);

        img.Image croppedImage =
            img.copyCrop(originalImage, x, y, width, height);
        croppedImages.add(croppedImage);
      }));
    }

    await Future.wait(cropFutures);

    setState(() {
      showCroppedImages = true;
    });
  }

  Future<void> _uploadToFirebase() async {
    if (croppedImages.isEmpty) return;

    FirebaseStorage storage = FirebaseStorage.instance;
    List<Future<void>> uploadFutures = [];

    for (var croppedImage in croppedImages) {
      String fileName = 'cropped_${DateTime.now().millisecondsSinceEpoch}.png';
      Reference ref = storage.ref().child('cropped_images/$fileName');

      Uint8List imageBytes = Uint8List.fromList(img.encodePng(croppedImage));

      uploadFutures.add(ref.putData(imageBytes).then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image uploaded successfully: $fileName')),
        );
      }).catchError((e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }));
    }

    await Future.wait(uploadFutures);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Finger Print Detector",
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 30, 30, 30),
      ),
      backgroundColor: const Color.fromARGB(255, 41, 41, 41),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isProcessing)
              const CircularProgressIndicator()
            else if (!showCroppedImages && _image != null)
              Expanded(
                child: _objectModel.renderBoxesOnImage(
                  _image!,
                  objDetect,
                  boxesColor: const Color.fromARGB(255, 255, 255, 255),
                  showPercentage: true,
                ),
              )
            else if (showCroppedImages)
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 3.5,
                          mainAxisSpacing: 3.5,
                        ),
                        itemCount: croppedImages.length,
                        itemBuilder: (BuildContext context, int index) {
                          return Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Image.memory(
                              Uint8List.fromList(
                                  img.encodePng(croppedImages[index])),
                              fit: BoxFit.cover,
                            ),
                          );
                        },
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _uploadToFirebase,
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all<Color>(
                            const Color.fromARGB(255, 46, 165, 64)),
                        padding: WidgetStateProperty.all<EdgeInsets>(
                            const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10)),
                        textStyle: WidgetStateProperty.all<TextStyle>(
                          const TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
                      child: const Text(
                        "Add to Firebase",
                        style: TextStyle(
                            color: Colors.white), // Set text color to white
                      ),
                    ),
                    // const SizedBox(height: 10),
                  ],
                ),
              )
            else
              Column(
                children: [
                  const SizedBox(height: 20),
                  Opacity(
                    opacity: 0.7,
                    child: Image.network(
                      'https://img.icons8.com/?size=100&id=82775&format=png&color=ffffff',
                      width: 100,
                      height: 100,
                    ),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: runObjectDetection,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all<Color>(
                          const Color.fromARGB(255, 46, 165, 64)),
                      padding: WidgetStateProperty.all<EdgeInsets>(
                          const EdgeInsets.symmetric(
                              horizontal: 35, vertical: 13)),
                      textStyle: WidgetStateProperty.all<TextStyle>(
                        const TextStyle(fontSize: 18),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "Scan Document",
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            if (_image != null && !showCroppedImages)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: ElevatedButton(
                  onPressed: _cropImages,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all<Color>(
                        const Color.fromARGB(
                            255, 46, 165, 64)), 
                    textStyle: WidgetStateProperty.all<TextStyle>(
                      const TextStyle(color: Colors.white),
                    ),
                  ),
                  child: const Text(
                    "Crop Images",
                    style: TextStyle(
                        fontSize: 18, 
                        color: Colors.white), // Set text color to white
                  ),
                ),
              ),
              const SizedBox(height: 35),
          ],
        ),
      ),
    );
  }
}