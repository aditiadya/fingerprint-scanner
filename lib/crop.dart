import 'dart:ui';
 
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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
  ImagePicker _picker = ImagePicker();
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
        pathObjectDetectionModel, 1, 640, 640,
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

        img.Image croppedImage = img.copyCrop(originalImage, x, y, width, height);
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
    return WillPopScope(
      onWillPop: () async {
        // Custom behavior on back button press, if needed
        return true; // Returning true allows the pop action
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Finger Print Detector"),
        ),
        backgroundColor: Colors.white,
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
                    boxesColor: const Color.fromRGBO(138, 114, 114, 0.612),
                    showPercentage: true,
                  ),
                )
              else if (showCroppedImages)
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 4.0,
                            mainAxisSpacing: 4.0,
                          ),
                          itemCount: croppedImages.length,
                          itemBuilder: (BuildContext context, int index) {
                            return Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Image.memory(
                                Uint8List.fromList(img.encodePng(croppedImages[index])),
                                fit: BoxFit.cover,
                              ),
                            );
                          },
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _uploadToFirebase,
                        child: const Text("Add to Firebase"),
                      ),
                    ],
                  ),
                )
              else
                const Text("Select the Camera to Begin Detections"),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: runObjectDetection,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.camera),
                    SizedBox(width: 8),
                    Text("Capture Image"),
                  ],
                ),
              ),
              if (_image != null && !showCroppedImages)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: ElevatedButton(
                    onPressed: _cropImages,
                    child: const Text("Crop Images"),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
