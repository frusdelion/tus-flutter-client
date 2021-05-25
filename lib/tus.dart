// Copyright 2020 Lionell Yip. All rights reserved.

import 'dart:core';

import 'package:flutter/services.dart';

typedef void OnCompleteCallback(String result, Tus tus);
typedef void OnProgressCallback(
    int bytesWritten, int bytesTotal, double progress, Tus tus);
typedef void OnErrorCallback(String error, Tus tus);

// The Tus Flutter client.
//
// Each tus flutter client supports one endpoint url to upload files to.
// If you need multiple tus upload endpoints, instantiate multiple tus clients.
class Tus {
  static const MethodChannel _channel =
      const MethodChannel('io.tus.flutter_service');

  // The endpoint url.
  final String endpointUrl;
  OnProgressCallback onProgress;
  OnCompleteCallback onComplete;
  OnErrorCallback onError;

  // Flag to ensure that the tus client is initialized.
  bool isInitialized = false;

  // Headers for client-wide uploads.
  Map<String, String> headers = Map<String, String>();

  // Number of retries before giving up. Defaults to infinite retries.
  int retry = -1;

  // [iOS-only] Allows cellular access for uploads.
  bool allowCellularAccess = true;

  Tus(this.endpointUrl,
      {this.onProgress,
      this.onComplete,
      this.onError,
      this.headers,
      this.allowCellularAccess}) {
    assert(endpointUrl != null);
    _channel.setMethodCallHandler(this.handler);
  }

  // Handles the method calls from the native side.
  Future<void> handler(MethodCall call) {
    // Ensure that the endpointUrl provided from the MethodChannel is the same
    // as the flutter client.
    switch (call.method) {
      case "progressBlock":
      case "resultBlock":
      case "failureBlock":
        if (call.arguments["endpointUrl"] != endpointUrl) {
          // This method call is not meant for this client.
          return null;
        }
        break;
    }

    // Trigger the onProgress callback if the callback is provided.
    if (call.method == "progressBlock") {
      var bytesWritten = int.tryParse(call.arguments["bytesWritten"]);
      var bytesTotal = int.tryParse(call.arguments["bytesTotal"]);      
      if (onProgress != null) {
        double progress = bytesWritten / bytesTotal;
        onProgress(bytesWritten, bytesTotal, progress, this);
      }
    }

    // Trigger the onComplete callback if the callback is provided.
    if (call.method == "resultBlock") {
      var resultUrl = call.arguments["resultUrl"];
      if (onComplete != null) {
        onComplete(resultUrl, this);
      }
    }

    // Triggers the onError callback if the callback is provided.
    if (call.method == "failureBlock") {
      var error = call.arguments["error"] ?? "";
      if (onError != null) {
        onError(error, this);
      }
    }
  }

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  // Initialize the tus client on the native side.
  Future<Map> initializeWithEndpoint() async {
    var response =
        await _channel.invokeMethod("initWithEndpoint", <String, String>{
      "endpointUrl": endpointUrl,
      "allowCellularAccess": allowCellularAccess.toString(),
    });

    isInitialized = true;

    return response;
  }

  // Performs a file upload using the tus protocol. Provide a [fileToUpload].
  // Optionally, you can provide [metadata] to enrich the file upload.
  // Note that filename is provided in the [metadata] upon upload.
  Future<dynamic> createUploadFromFile(String fileToUpload,
      {Map<String, String> metadata}) async {
    if (!isInitialized) {
      await initializeWithEndpoint();
    }

    // Ensures that metadata is not null by providing an empty map, if not
    // provided by the user.
    if (metadata == null) {
      metadata = Map<String, String>();
    }

    try {
      var result = await _channel
          .invokeMapMethod("createUploadFromFile", <String, dynamic>{
        "endpointUrl": endpointUrl,
        "fileUploadUrl": fileToUpload,
        "retry": retry.toString(),
        "headers": headers,
        "metadata": metadata,
      });

      if (result.containsKey("error")) {
        throw Exception("${result["error"]} { ${result["reason"]}");
      }

      return result;
    } catch (error) {
      throw error;
    }
  }
}
