// Copyright 2020 Lionell Yip. All rights reserved.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tus/tus.dart';

final String endpointUrl = "http://127.0.0.1:8080/files";
final String authorizationHeader = "Bearer JWT";

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  Tus tusD;

  double progressBar = 0;
  bool inProgress = false;
  String resultText = "";

  @override
  void initState() {
    super.initState();
    initPlatformState();
    progressBar = 0.0;
  }

  File _image;

  Future getImage() async {
    var image = await ImagePicker.pickImage(source: ImageSource.gallery);

    setState(() {
      _image = image;
    });
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      platformVersion = await Tus.platformVersion;
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    tusD = Tus(endpointUrl);

    tusD.headers = <String, String>{
      "Authorization": authorizationHeader,
    };

    var response = await tusD.initializeWithEndpoint();
    response.forEach((dynamic key, dynamic value) {
      print("[$key] $value");
    });
    tusD.onError = (String error, Tus tus) {
      print(error);
      setState(() {
        progressBar = 0.0;
        inProgress = true;
        resultText = error;
      });
    };

    tusD.onProgress =
        (int bytesWritten, int bytesTotal, double progress, Tus tus) {
      setState(() {
        progressBar = (bytesWritten / bytesTotal);
      });
    };

    tusD.onComplete = (String result, Tus tus) {
      print("File can be found: $result");
      setState(() {
        inProgress = true;
        progressBar = 1.0;
        resultText = result;
      });
    };

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Tus Flutter Client Upload Demo'),
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Center(
              child: Text('Running on: $_platformVersion\n'),
            ),
            RaisedButton(
              child: Text("Choose a photo to upload!"),
              onPressed: () async {
                await getImage();
                setState(() {
                  inProgress = true;
                  progressBar = 0;
                });
                print(await tusD.createUploadFromFile(
                  _image.path,
                  metadata: <String, String>{
                    "test": "message",
                  },
                ));
              },
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: inProgress
                  ? LinearProgressIndicator(
                      value: progressBar,
                    )
                  : Container(),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(resultText),
            ),
          ],
        ),
      ),
    );
  }
}
