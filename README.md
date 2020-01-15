# tus-flutter-client
[![Protocol](https://img.shields.io/badge/tus_protocol-v1.0.0-blue.svg?style=flat)](http://tus.io/protocols/resumable-upload.html)

A Flutter plugin to upload files using the [tus resumable upload protocol](https://tus.io):
* [TUSKit](https://github.com/tus/TUSKit) on iOS
* [tus-android-client](https://github.com/tus/tus-android-client) on Android

## Features
* Supports multiple upload endpoints.
* Callbacks for the following events: Progress, Completed and Error.

## Pull Requests and Issues
Pull requests are always welcome! 

## Installation
Add the following to your `pubspec.yml`
```yaml
dependencies:
  #...
  tus: 0.0.1
```

## Getting Started
```dart
import 'package:tus/tus.dart';

// Create tus client
var tusD = Tus(endpointUrl);

// Setup tus headers
tusD.headers = <String, String>{
  "Authorization": authorizationHeader,
};

// Initialize the tus client
var response = await tusD.initializeWithEndpoint();
response.forEach((dynamic key, dynamic value) {
  print("[$key] $value");
});

// Callbacks for tus events
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

// Trigger file upload.
//
await tusD.createUploadFromFile(
    path, // local path on device i.e. /storage/.../image.jpg
    metadata: <String, String>{ // additional metadata 
      "test": "message",
    },
);

// Get the result from your onComplete callback
```

## Future Work
* [ ] Write tests and code coverage
* [ ] tus client for the web

## License
MIT