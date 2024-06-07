import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';


late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigoAccent),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Live Camera Image Recognition',),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late CameraController controller;
  late ImageLabeler imageLabeler;
  bool isBusy = false;

  @override
  void initState() {
    super.initState();
    final ImageLabelerOptions options = ImageLabelerOptions(confidenceThreshold: 0.5);
    imageLabeler = ImageLabeler(options: options);
    controller = CameraController(
      _cameras[0],
      ResolutionPreset.max,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }

      controller.startImageStream((image) {
        if (!isBusy) {
          isBusy = true;
          doImageLabelling(image);
        }
      });

      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
          // Handle access errors here.
            break;
          default:
          // Handle other errors here.
            break;
        }
      }
    });
  }

  String result = "result";

  doImageLabelling(CameraImage img) async {
    try {
      result = "";
      InputImage? inputImage = _inputImageFromCameraImage(img);
      if (inputImage != null) {
        final List<ImageLabel> labels = await imageLabeler.processImage(inputImage);
        for (ImageLabel label in labels) {
          final String text = label.label;
          final double confidence = label.confidence;
          result += "$text ${confidence.toStringAsFixed(2)}\n";
          print("$text ${confidence.toStringAsFixed(2)}\n");
        }
        setState(() {
          isBusy = false;
        });
      } else {
        setState(() {
          result = "Error processing image";
          isBusy = false;
        });
      }
    } catch (e) {
      print("Error during image labelling: $e");
      setState(() {
        result = "Error during image labelling";
        isBusy = false;
      });
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameras[0];
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final rotationCompensation = _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      final correctedOrientation = camera.lensDirection == CameraLensDirection.front
          ? (sensorOrientation + rotationCompensation) % 360
          : (sensorOrientation - rotationCompensation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(correctedOrientation);
    }
    if (rotation == null) return null;

    if (Platform.isAndroid && image.format.group == ImageFormatGroup.yuv420) {
      try {
        final allBytes = WriteBuffer()
          ..putUint8List(image.planes[0].bytes)
          ..putUint8List(image.planes[1].bytes)
          ..putUint8List(image.planes[2].bytes);
        final bytes = allBytes.done().buffer.asUint8List();
        final size = Size(image.width.toDouble(), image.height.toDouble());

        return InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: size,
            rotation: rotation,
            format: InputImageFormat.yuv420,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );
      } catch (e) {
        print("Error converting image: $e");
        return null;
      }
    } else if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    return null;
  }

  final Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Image Recognizer", style: TextStyle(color: Colors.white,),),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              controller.value.isInitialized
                  ? Container(
                margin: EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15.0),
                  child: Container(
                    height: MediaQuery.of(context).size.height - 300,
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
              )
                  : Container(),
              Card(
                color: Colors.indigoAccent.shade700,
                margin: const EdgeInsets.all(10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  width: MediaQuery.of(context).size.width,
                  height: 150,
                  child: Text(result, style: const TextStyle(color: Colors.deepOrangeAccent, fontSize: 14),),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



