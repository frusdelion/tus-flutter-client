// Copyright 2020 Lionell Yip. All rights reserved.

import 'dart:core';

import 'package:flutter/services.dart';

typedef void OnCompleteCallback(String result, Tus tus);
typedef void OnProgressCallback(
    int bytesWritten, int bytesTotal, double progress, Tus tus);
typedef void OnErrorCallback(String error, Tus tus);

class Tus {
  static const MethodChannel _channel =
      const MethodChannel('io.tus.flutter_service');

  final String endpointUrl;
  OnProgressCallback onProgress;
  OnCompleteCallback onComplete;
  OnErrorCallback onError;
  bool isInitialized = false;
  Map<String, String> headers = Map<String, String>();
  int retry = -1;
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

  Future<void> handler(MethodCall call) {
    switch (call.method) {
      case "progressBlock":
      case "resultBlock":
      case "failureBlock":
        if (call.arguments["endpointUrl"] != endpointUrl) {
          throw Exception(
              'endpoint url ${call.arguments["endpointUrl"]} not recognised.');
        }
        break;
    }

    if (call.method == "progressBlock") {
      var bytesWritten = call.arguments["bytesWritten"];
      var bytesTotal = call.arguments["bytesTotal"];
      if (onProgress != null) {
        double progress = bytesWritten / bytesTotal;
        onProgress(int.tryParse(bytesWritten), int.tryParse(bytesTotal),
            progress, this);
      }
    }

    if (call.method == "resultBlock") {
      var resultUrl = call.arguments["resultUrl"];
      if (onComplete != null) {
        onComplete(resultUrl, this);
      }
    }

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

  Future<Map> initializeWithEndpoint() async {
    var response =
        await _channel.invokeMethod("initWithEndpoint", <String, String>{
      "endpointUrl": endpointUrl,
      "allowCellularAccess": allowCellularAccess.toString(),
    });

    isInitialized = true;

    return response;
  }

  Future<Map<String, Object>> createUploadFromFile(String fileToUpload,
      {Map<String, String> metadata}) async {
    if(metadata == null) {
      metadata = Map<String,String>();
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

      if(result.containsKey("error")) {
        throw Exception("${result["error"]} { ${result["reason"]}");
      }

      return result;
    } catch (error) {
      throw error;
    }
  }
}
