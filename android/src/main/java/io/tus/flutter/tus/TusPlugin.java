// Copyright 2020 Lionell Yip. All rights reserved.
package io.tus.flutter.tus;

import android.content.SharedPreferences;
import android.os.AsyncTask;
import android.os.Handler;
import android.os.Looper;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.HashMap;
import java.util.concurrent.ExecutionException;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.tus.android.client.TusPreferencesURLStore;
import io.tus.java.client.ProtocolException;
import io.tus.java.client.TusClient;
import io.tus.java.client.TusExecutor;
import io.tus.java.client.TusUpload;
import io.tus.java.client.TusUploader;


/**
 * TusPlugin
 */
public class TusPlugin implements FlutterPlugin, MethodCallHandler {
    private static final String CHANNEL = "io.tus.flutter_service";
    private static final String CACHE_FILE_NAME = "tuskit_example";

    private SharedPreferences sharedPreferences;
    private HashMap<String, TusClient> clients = new HashMap<>();
    private MethodChannel methodChannel;

    // This static function is optional and equivalent to onAttachedToEngine. It supports the old
    // pre-Flutter-1.12 Android projects. You are encouraged to continue supporting
    // plugin registration via this function while apps migrate to use the new Android APIs
    // post-flutter-1.12 via https://flutter.dev/go/android-project-migration.
    //
    // It is encouraged to share logic between onAttachedToEngine and registerWith to keep
    // them functionally equivalent. Only one of onAttachedToEngine or registerWith will be called
    // depending on the user's project. onAttachedToEngine or registerWith must both be defined
    // in the same class.
    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), CHANNEL);
        TusPlugin tusPlugin = new TusPlugin();
        tusPlugin.methodChannel = channel;
        tusPlugin.sharedPreferences = registrar.activeContext().getSharedPreferences("tus", 0);
        channel.setMethodCallHandler(tusPlugin);
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        final MethodChannel channel = new MethodChannel(flutterPluginBinding.getFlutterEngine().getDartExecutor(), CHANNEL);
        TusPlugin tusPlugin = new TusPlugin();
        tusPlugin.methodChannel = channel;
        tusPlugin.sharedPreferences = flutterPluginBinding.getApplicationContext().getSharedPreferences("tus", 0);
        channel.setMethodCallHandler(tusPlugin);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        if (call.method.equals("getPlatformVersion")) {
            result.success("Android " + android.os.Build.VERSION.RELEASE);
        } else if (call.method.equals("initWithEndpoint")) {
            HashMap<String, Object> arguments = (HashMap<String, Object>) call.arguments;

            String endpointUrl = (String) arguments.get("endpointUrl");
            if (endpointUrl.isEmpty()) {
                result.error("InvalidEndpointUrl", "did not provide endpoint url", null);
                return;
            }

            TusClient tusClient = new TusClient();
            tusClient.enableResuming(new TusPreferencesURLStore(sharedPreferences));             
            clients.put(endpointUrl, tusClient);

            HashMap<String, String> a = new HashMap<>();
            a.put("endpointUrl", endpointUrl);
            result.success(a);
        } else if (call.method.equals("createUploadFromFile")) {
            System.out.println("Preparing upload");

            HashMap<String, Object> arguments = (HashMap<String, Object>) call.arguments;

            final String endpointUrl = (String) arguments.get("endpointUrl");
            final TusClient client = this.clients.get(endpointUrl);
            if (client == null) {
                result.error("EndpointURLUnintialized", "endpoint url was not previously initialized", "You need to call initWithEndpoint before calling this method with the same endpointUrl");
                return;
            }

            String fileUploadUrl = (String) arguments.get("fileUploadUrl");
            if (fileUploadUrl.isEmpty()) {
                result.error("InvalidFileUploadUrlProvided", "file upload url is invalid.", "Provide a local path to the file.");
                return;
            }

            HashMap<String, String> headers = new HashMap<>();
            if (arguments.containsKey("headers")) {
                headers = (HashMap<String, String>) arguments.get("headers");
            }

            client.setHeaders(headers);

            HashMap<String, String> metadata = new HashMap<>();
            if (arguments.containsKey("metadata")) {
                metadata = (HashMap<String, String>) arguments.get("metadata");
            }

            int retryCount = -1;
            if (arguments.containsKey("retry")) {
                retryCount = Integer.parseInt(String.valueOf(arguments.get("retry")));
            }

            System.out.println("Starting upload");

            HandleFileUpload b = new HandleFileUpload(result, client, fileUploadUrl, methodChannel, endpointUrl, metadata);
            try {
                b.execute();
            }
            catch (Exception e) {
                StringWriter errors = new StringWriter();
                e.printStackTrace(new PrintWriter(errors));
                result.error("Exception", e.getMessage(), errors.toString());
            }
        } else {
            result.notImplemented();
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        for (TusClient client : clients.values()) {
            client.disableRemoveFingerprintOnSuccess();
        }
    }
}

class HandleFileUpload extends AsyncTask<Void, HashMap<String, String>, HashMap<String, String>> {

    final TusClient client;
    final String uploadFileUrl;
    final MethodChannel methodChannel;
    final String endpointUrl;
    final HashMap<String, String> metadata;
    final Result result;

    HandleFileUpload(Result result, TusClient client, String uploadFileUrl, MethodChannel methodChannel, String endpointUrl, HashMap<String, String> metadata) {
        this.result = result;
        this.client = client;
        this.uploadFileUrl = uploadFileUrl;
        this.methodChannel = methodChannel;
        this.endpointUrl = endpointUrl;
        this.metadata = metadata;
    }

    @Override
    protected HashMap<String, String> doInBackground(Void... voids) {

        File file = new File(uploadFileUrl);
        final TusUpload upload;
        try {
            upload = new TusUpload(file);
            metadata.put("filename", file.getName());
            upload.setMetadata(metadata);
        } catch (FileNotFoundException e) {
            StringWriter errors = new StringWriter();
            e.printStackTrace(new PrintWriter(errors));
            final HashMap<String, String> a = new HashMap<>();
            a.put("error", e.getMessage());
            a.put("reason", errors.toString());
            return a;
        }

        // We wrap our uploading code in the TusExecutor class which will automatically catch
        // exceptions and issue retries with small delays between them and take fully
        // advantage of tus' resumability to offer more reliability.
        // This step is optional but highly recommended.
        TusExecutor tusExecutor = new TusExecutor() {
            @Override
            protected void makeAttempt() throws ProtocolException, IOException {
                // First try to resume an upload. If that's not possible we will create a new
                // upload and get a TusUploader in return. This class is responsible for opening
                // a connection to the remote server and doing the uploading.                  
                final TusUploader uploader = client.beginOrResumeUploadFromURL(upload, new URL(endpointUrl));

                // Upload the file as long as data is available. Once the
                // file has been fully uploaded the method will return -1
                do {
                    long totalBytes = upload.getSize();
                    long bytesUploaded = uploader.getOffset();
                    double progress = (double) bytesUploaded / totalBytes * 100;

                    System.out.printf("Upload at %06.2f%%.\n", progress);

                    final HashMap<String, String> a = new HashMap<>();
                    a.put("endpointUrl", endpointUrl);
                    a.put("bytesWritten", Long.toString(bytesUploaded));
                    a.put("bytesTotal", Long.toString(totalBytes));
                    new Handler(Looper.getMainLooper()).post(new Runnable() {
                        @Override
                        public void run() {
                            // Call the desired channel message here.
                            methodChannel.invokeMethod("progressBlock", a);
                        }
                    });

                } while (uploader.uploadChunk() > -1);

                uploader.finish();
                System.out.println("Completed upload");

                final HashMap<String, String> s = new HashMap<>();
                s.put("endpointUrl", endpointUrl);
                s.put("resultUrl", uploader.getUploadURL().toString());
                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override
                    public void run() {
                        // Call the desired channel message here.
                        methodChannel.invokeMethod("resultBlock", s);
                        result.success(s);
                    }
                });
            }
        };

        try {
            tusExecutor.makeAttempts();
            HashMap<String, String> a = new HashMap<>();
            a.put("inProgress", "true");
            return a;
        } catch (ProtocolException e) {
            System.out.println(e.getMessage());
            final HashMap<String, String> errorMap = new HashMap<>();
            errorMap.put("endpointUrl", endpointUrl);
            errorMap.put("error", e.getMessage());
            StringWriter errors = new StringWriter();
            e.printStackTrace(new PrintWriter(errors));
            errorMap.put("reason", errors.toString());

            new Handler(Looper.getMainLooper()).post(new Runnable() {
                @Override
                public void run() {
                    // Call the desired channel message here.
                    methodChannel.invokeMethod("failureBlock", errorMap);
                    result.error("ErrorFromExecution", errorMap.get("error"), errorMap.get("reason"));
                }
            });

            return errorMap;
        } catch (IOException e) {
            final HashMap<String, String> errorMap = new HashMap<>();
            errorMap.put("endpointUrl", endpointUrl);
            errorMap.put("error", e.getMessage());

            StringWriter errors = new StringWriter();
            e.printStackTrace(new PrintWriter(errors));
            errorMap.put("reason", errors.toString());

            new Handler(Looper.getMainLooper()).post(new Runnable() {
                @Override
                public void run() {
                    // Call the desired channel message here.
                    methodChannel.invokeMethod("failureBlock", errorMap);
                    result.error("ErrorFromExecution", errorMap.get("error"), errorMap.get("reason"));
                }
            });

            return errorMap;

        } catch (Exception e) {
            final HashMap<String, String> errorMap = new HashMap<>();
            errorMap.put("endpointUrl", endpointUrl);
            errorMap.put("error", e.getMessage());

            StringWriter errors = new StringWriter();
            e.printStackTrace(new PrintWriter(errors));
            errorMap.put("reason", errors.toString());

            new Handler(Looper.getMainLooper()).post(new Runnable() {
                @Override
                public void run() {
                    // Call the desired channel message here.
                    methodChannel.invokeMethod("failureBlock", errorMap);
                    result.error("ErrorFromExecution", errorMap.get("error"), errorMap.get("reason"));
                }
            });
            return errorMap;
        }

    }
}
