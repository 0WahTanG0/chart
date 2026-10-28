package app.grafiksmen;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.DownloadManager;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.print.PrintAttributes;
import android.print.PrintManager;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Оболочка для веб-версии графика смен.
 * Страница открывается с постоянного адреса https://appassets.androidplatform.net/, поэтому
 * сохранённые данные (localStorage) не теряются ни при обновлении страницы, ни при обновлении APK.
 * Новая страница скачивается в фоне из version.json; новый APK скачивается и предлагается к установке.
 */
public class MainActivity extends Activity {
    private static final String HOST = "appassets.androidplatform.net";
    private static final String HOME = "https://" + HOST + "/index.html";
    private static final String APK_MIME = "application/vnd.android.package-archive";
    private static final Pattern BUILD = Pattern.compile("WEB_BUILD = (\\d+)");
    private static final int PICK_FILE = 7;

    private WebView web;
    private SharedPreferences prefs;
    private ValueCallback<Uri[]> fileCallback;
    private WebView printView;
    private int bundledBuild;
    private long apkDownloadId = -1;
    private boolean checking;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = getSharedPreferences("app", MODE_PRIVATE);
        bundledBuild = readBundledBuild();

        FrameLayout root = new FrameLayout(this);
        web = new WebView(this);
        root.addView(web, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);
        setupWindow(root);

        WebSettings ws = web.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setAllowFileAccess(false);
        ws.setAllowContentAccess(false);
        ws.setTextZoom(100);
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return serve(request.getUrl());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (HOST.equals(uri.getHost())) return false;
                openExternal(uri.toString());
                return true;
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (fileCallback != null) fileCallback.onReceiveValue(null);
                fileCallback = callback;
                Intent pick = new Intent(Intent.ACTION_GET_CONTENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");
                try {
                    startActivityForResult(Intent.createChooser(pick, "Выберите файл копии"), PICK_FILE);
                    return true;
                } catch (Exception e) {
                    fileCallback = null;
                    return false;
                }
            }
        });
        web.addJavascriptInterface(new Bridge(), "AndroidApp");
        web.loadUrl(HOME);
        checkUpdates(false);
    }

    private void setupWindow(View root) {
        boolean night = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        int bar = night ? 0xFF171B23 : 0xFFFFFFFF;
        root.setBackgroundColor(bar);
        web.setBackgroundColor(night ? 0xFF0E1117 : 0xFFECEFF4);
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
            getWindow().setStatusBarColor(Color.TRANSPARENT);
            getWindow().setNavigationBarColor(Color.TRANSPARENT);
            WindowInsetsController controller = getWindow().getInsetsController();
            int light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
            if (controller != null) controller.setSystemBarsAppearance(night ? 0 : light, light);
            root.setOnApplyWindowInsetsListener((v, insets) -> {
                Insets b = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime() | WindowInsets.Type.displayCutout());
                v.setPadding(b.left, b.top, b.right, b.bottom);
                return WindowInsets.CONSUMED;
            });
        } else {
            getWindow().setStatusBarColor(bar);
            getWindow().setNavigationBarColor(bar);
            if (!night) getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        }
    }

    /* ---------- Страница: встроенная или скачанная обновлением ---------- */

    private File downloadedPage() {
        return new File(new File(getFilesDir(), "web"), "index.html");
    }

    private int currentBuild() {
        int downloaded = prefs.getInt("webBuild", 0);
        return downloaded > bundledBuild && downloadedPage().exists() ? downloaded : bundledBuild;
    }

    private WebResourceResponse serve(Uri uri) {
        if (!HOST.equals(uri.getHost())) return null;
        String path = uri.getPath();
        if (path == null || path.equals("/") || path.equals("/index.html")) {
            try {
                InputStream in = currentBuild() > bundledBuild ? new FileInputStream(downloadedPage()) : getAssets().open("web/index.html");
                WebResourceResponse response = new WebResourceResponse("text/html", "utf-8", in);
                response.setResponseHeaders(Collections.singletonMap("Cache-Control", "no-store"));
                return response;
            } catch (IOException e) {
                return null;
            }
        }
        return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found", null, null);
    }

    private int readBundledBuild() {
        try (InputStream in = getAssets().open("web/index.html")) {
            return pageBuild(new String(readAll(in), StandardCharsets.UTF_8));
        } catch (IOException e) {
            return 0;
        }
    }

    private static int pageBuild(String html) {
        Matcher m = BUILD.matcher(html);
        return m.find() ? Integer.parseInt(m.group(1)) : 0;
    }

    /* ---------- Обновления ---------- */

    private void checkUpdates(boolean manual) {
        if (checking) return;
        checking = true;
        new Thread(() -> {
            try {
                JSONObject info = new JSONObject(httpGet(BuildConfig.UPDATE_URL + "?t=" + System.currentTimeMillis()));
                int apk = info.optInt("apkVersionCode"), page = info.optInt("webBuild");
                String notes = info.optString("notes");
                if (apk > BuildConfig.VERSION_CODE) {
                    String url = info.getString("apkUrl"), name = info.optString("apkVersionName");
                    runOnUiThread(() -> askInstallApk(url, name, notes));
                } else if (page > currentBuild()) {
                    String html = httpGet(info.getString("webUrl") + "?t=" + System.currentTimeMillis());
                    if (pageBuild(html) != page || !html.contains("<title>График смен</title>")) throw new IOException("Повреждённая страница");
                    File target = downloadedPage(), tmp = new File(target.getParentFile(), "index.tmp");
                    target.getParentFile().mkdirs();
                    try (OutputStream out = new FileOutputStream(tmp)) { out.write(html.getBytes(StandardCharsets.UTF_8)); }
                    if (!tmp.renameTo(target)) throw new IOException("Не удалось сохранить страницу");
                    prefs.edit().putInt("webBuild", page).apply();
                    String version = info.optString("webVersion");
                    runOnUiThread(() -> askReload(version, notes));
                } else if (manual) {
                    runOnUiThread(() -> toast("У вас последняя версия"));
                }
            } catch (Exception e) {
                if (manual) runOnUiThread(() -> toast("Не удалось проверить обновления. Проверьте интернет."));
            } finally {
                checking = false;
            }
        }).start();
    }

    private void askReload(String version, String notes) {
        if (isFinishing()) return;
        new AlertDialog.Builder(this)
                .setTitle("Обновление " + version + " готово")
                .setMessage((notes.isEmpty() ? "" : notes + "\n\n") + "Ваши данные сохранятся.")
                .setPositiveButton("Обновить сейчас", (d, w) -> web.loadUrl(HOME))
                .setNegativeButton("Позже", null)
                .show();
    }

    private void askInstallApk(String url, String version, String notes) {
        if (isFinishing()) return;
        new AlertDialog.Builder(this)
                .setTitle("Новая версия приложения " + version)
                .setMessage((notes.isEmpty() ? "" : notes + "\n\n") + "Скачать и установить? Ваши данные сохранятся.")
                .setPositiveButton("Установить", (d, w) -> downloadApk(url))
                .setNegativeButton("Позже", null)
                .show();
    }

    private void downloadApk(String url) {
        try {
            File old = new File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "grafik-smen-update.apk");
            if (old.exists()) old.delete();
            DownloadManager dm = getSystemService(DownloadManager.class);
            DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url))
                    .setTitle("График смен — обновление")
                    .setMimeType(APK_MIME)
                    .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                    .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, "grafik-smen-update.apk");
            apkDownloadId = dm.enqueue(request);
            IntentFilter filter = new IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE);
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(apkReceiver, filter, Context.RECEIVER_EXPORTED);
            else registerReceiver(apkReceiver, filter);
            toast("Скачиваю обновление…");
        } catch (Exception e) {
            openExternal(url);
        }
    }

    private final BroadcastReceiver apkReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1) != apkDownloadId) return;
            try { unregisterReceiver(this); } catch (Exception ignored) { }
            Uri apk = getSystemService(DownloadManager.class).getUriForDownloadedFile(apkDownloadId);
            if (apk == null) { toast("Не удалось скачать обновление"); return; }
            Intent install = new Intent(Intent.ACTION_VIEW).setDataAndType(apk, APK_MIME)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            try { startActivity(install); } catch (Exception e) { toast("Откройте загруженный файл из уведомления, чтобы установить"); }
        }
    };

    /* ---------- Файлы, картинки, печать ---------- */

    private static byte[] decodeDataUrl(String dataUrl) {
        return Base64.decode(dataUrl.substring(dataUrl.indexOf(',') + 1), Base64.DEFAULT);
    }

    private Uri insertMedia(Uri collection, String name, String mime, String dir, byte[] bytes) throws IOException {
        ContentResolver resolver = getContentResolver();
        ContentValues values = new ContentValues();
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
        values.put(MediaStore.MediaColumns.MIME_TYPE, mime);
        values.put(MediaStore.MediaColumns.RELATIVE_PATH, dir);
        Uri uri = resolver.insert(collection, values);
        if (uri == null) throw new IOException("Нет доступа к хранилищу");
        try (OutputStream out = resolver.openOutputStream(uri)) {
            if (out == null) throw new IOException("Нет доступа к хранилищу");
            out.write(bytes);
        }
        return uri;
    }

    private void shareImage(String dataUrl) throws IOException {
        shareBytes("grafik.png", "image/png", decodeDataUrl(dataUrl));
    }

    private void shareBytes(String name, String mime, byte[] bytes) throws IOException {
        File dir = new File(getCacheDir(), "share");
        dir.mkdirs();
        try (OutputStream out = new FileOutputStream(new File(dir, name))) { out.write(bytes); }
        Uri uri = Uri.parse("content://app.grafiksmen.share/" + Uri.encode(name));
        Intent send = new Intent(Intent.ACTION_SEND).setType(mime)
                .putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        send.setClipData(ClipData.newRawUri("График смен", uri));
        startActivity(Intent.createChooser(send, "Отправить график"));
    }

    private void printImage(String dataUrl) {
        printView = new WebView(this);
        printView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                PrintManager pm = getSystemService(PrintManager.class);
                PrintAttributes attrs = new PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4.asLandscape()).build();
                pm.print("График смен", view.createPrintDocumentAdapter("График смен"), attrs);
            }
        });
        printView.loadDataWithBaseURL(null, "<html><body style=\"margin:0\"><img src=\"" + dataUrl + "\" style=\"width:100%\"></body></html>", "text/html", "utf-8", null);
    }

    private class Bridge {
        @JavascriptInterface
        public String version() {
            return BuildConfig.VERSION_NAME;
        }

        @JavascriptInterface
        public void checkUpdates() {
            runOnUiThread(() -> MainActivity.this.checkUpdates(true));
        }

        @JavascriptInterface
        public void shareImage(String dataUrl) {
            runOnUiThread(() -> {
                try { MainActivity.this.shareImage(dataUrl); } catch (Exception e) { toast("Не удалось отправить картинку"); }
            });
        }

        @JavascriptInterface
        public void saveImage(String dataUrl, String name) {
            runOnUiThread(() -> {
                try {
                    insertMedia(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, name, "image/png", Environment.DIRECTORY_PICTURES + "/График смен", decodeDataUrl(dataUrl));
                    toast("Сохранено в галерею");
                } catch (Exception e) { toast("Не удалось сохранить картинку"); }
            });
        }

        @JavascriptInterface
        public void saveText(String name, String text) {
            runOnUiThread(() -> {
                try {
                    insertMedia(MediaStore.Downloads.EXTERNAL_CONTENT_URI, name, "application/json", Environment.DIRECTORY_DOWNLOADS, text.getBytes(StandardCharsets.UTF_8));
                    toast("Копия сохранена в «Загрузки»: " + name);
                } catch (Exception e) { toast("Не удалось сохранить файл"); }
            });
        }

        @JavascriptInterface
        public void saveFile(String name, String base64, String mime) {
            runOnUiThread(() -> {
                try {
                    insertMedia(MediaStore.Downloads.EXTERNAL_CONTENT_URI, name, mime, Environment.DIRECTORY_DOWNLOADS, Base64.decode(base64, Base64.DEFAULT));
                    toast("Сохранено в «Загрузки»: " + name);
                } catch (Exception e) { toast("Не удалось сохранить файл"); }
            });
        }

        @JavascriptInterface
        public void shareFile(String name, String base64, String mime) {
            runOnUiThread(() -> {
                try { shareBytes(name, mime, Base64.decode(base64, Base64.DEFAULT)); } catch (Exception e) { toast("Не удалось отправить файл"); }
            });
        }

        @JavascriptInterface
        public void printImage(String dataUrl) {
            runOnUiThread(() -> MainActivity.this.printImage(dataUrl));
        }
    }

    /* ---------- Служебное ---------- */

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == PICK_FILE && fileCallback != null) {
            fileCallback.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data));
            fileCallback = null;
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        web.evaluateJavascript("window.appBack ? appBack() : false", result -> {
            if (!"true".equals(result)) MainActivity.super.onBackPressed();
        });
    }

    private void openExternal(String url) {
        try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); } catch (Exception ignored) { }
    }

    private void toast(String text) {
        Toast.makeText(this, text, Toast.LENGTH_LONG).show();
    }

    private static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[16384];
        for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
        return out.toByteArray();
    }

    private static String httpGet(String url) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(30000);
        c.setRequestProperty("Cache-Control", "no-cache");
        try {
            if (c.getResponseCode() != 200) throw new IOException("HTTP " + c.getResponseCode());
            try (InputStream in = c.getInputStream()) { return new String(readAll(in), StandardCharsets.UTF_8); }
        } finally {
            c.disconnect();
        }
    }
}
