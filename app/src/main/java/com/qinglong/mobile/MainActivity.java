package com.qinglong.mobile;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.res.AssetFileDescriptor;
import android.database.Cursor;
import android.os.Bundle;
import android.os.Build;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.PersistableBundle;
import android.provider.OpenableColumns;
import android.graphics.Color;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.net.Uri;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.net.URI;
import java.util.UUID;
import java.util.HashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.Future;
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** The UI is bundled offline; only the native API client communicates with the user's server. */
public final class MainActivity extends Activity {
    private static final String ORIGIN = "https://app.qinglong.local";
    private WebView web;
    private GlassDockView dock;
    private GlassDockHost dockHost;
    private long dockRequest;
    private String dockDocument;
    private ProfileStore store;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final HashMap<String, QinglongApi> clients = new HashMap<>();
    private volatile boolean destroyed;
    private long lastHapticAt;
    private static final AtomicInteger NEXT_PICK_CODE = new AtomicInteger(0x4A00);
    private static final long PICK_TIMEOUT_MS = 140_000L;
    private final Handler pickerHandler = new Handler(Looper.getMainLooper());
    private final HashMap<Integer, ScriptPick> scriptPicks = new HashMap<>();
    // A stalled cloud document must never block API requests or create an
    // unbounded set of reader threads. A third stalled read fails explicitly.
    private final ExecutorService fileWorker = new ThreadPoolExecutor(0, 2, 30,
        TimeUnit.SECONDS, new SynchronousQueue<>());
    private boolean pickerInterrupted;
    private volatile float statusBarInset;
    private static final int JD_LOGIN_CODE = 0x4901;
    private String jdLoginRequest;
    private final Runnable jdLoginTimeout = () -> cancelJdLogin("timeout");

    private void applySystemBars(boolean dark) {
        android.view.Window window = getWindow();
        if (Build.VERSION.SDK_INT >= 30) window.setDecorFitsSystemWindows(false);
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(dark ? Color.rgb(20,24,32) : Color.rgb(237,240,244));
        if (Build.VERSION.SDK_INT >= 29) window.setStatusBarContrastEnforced(false);
        int layout = android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            | android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            | android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION;
        window.getDecorView().setSystemUiVisibility(layout | (dark ? 0
            : android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR));
        if (Build.VERSION.SDK_INT >= 28) {
            android.view.WindowManager.LayoutParams attributes = window.getAttributes();
            attributes.layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            window.setAttributes(attributes);
        }
    }

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        pickerInterrupted = saved != null && saved.getBoolean("scriptPickerInterrupted", false);
        applySystemBars(false);
        int statusResource = getResources().getIdentifier("status_bar_height", "dimen", "android");
        statusBarInset = statusResource == 0 ? 0 : getResources().getDimensionPixelSize(statusResource) / getResources().getDisplayMetrics().density;
        store = new ProfileStore(this);
        WebView.setWebContentsDebuggingEnabled(
            (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0);
        web = new WebView(this) {
            @Override protected void onDraw(android.graphics.Canvas canvas) {
                super.onDraw(canvas);
                if (dockHost != null) dockHost.requestAnimatedSample();
            }
        };
        web.setOnScrollChangeListener((view,x,y,oldX,oldY) -> { if (dockHost != null) dockHost.requestSample(); });
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        settings.setSaveFormData(false);
        if (Build.VERSION.SDK_INT >= 26) settings.setSafeBrowsingEnabled(true);
        web.setBackgroundColor(Color.rgb(237,240,244));
        web.addJavascriptInterface(new Bridge(), "NativeBridge");
        web.setWebViewClient(new WebViewClient() {
            @Override public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                dockRequest = 0; dockDocument = null;
                if (dockHost != null) dockHost.applyState("tasks", false, false, false, true);
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) { return true; }
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                try {
                    if (!"https".equals(uri.getScheme()) || !"app.qinglong.local".equals(uri.getHost())) return blocked();
                    String path = uri.getPath();
                    if (path == null || path.equals("/")) path = "/index.html";
                    if (!(path.equals("/index.html") || path.equals("/app.css") || path.equals("/app.js") || path.equals("/advanced.js") || path.equals("/jd-cookie.js") || path.equals("/editor.js") || path.equals("/features.js") || path.equals("/page-cache.js") || path.equals("/dashboard.js") || path.equals("/interactions.js") || path.equals("/polish.css") || path.equals("/reference-layout.css") || path.equals("/app-icon.png"))) return blocked();
                    String mime = path.endsWith("png") ? "image/png" : path.endsWith("css") ? "text/css" : path.endsWith("js") ? "text/javascript" : "text/html";
                    WebResourceResponse response = new WebResourceResponse(mime, "UTF-8", getAssets().open(path.substring(1)));
                    HashMap<String,String> headers = new HashMap<>();
                    headers.put("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'none'; base-uri 'none'; frame-src 'none'; object-src 'none'");
                    headers.put("Cache-Control", "no-store");
                    headers.put("X-Content-Type-Options", "nosniff");
                    response.setResponseHeaders(headers);
                    return response;
                } catch (Exception e) { return blocked(); }
            }
        });
        android.widget.FrameLayout root = new android.widget.FrameLayout(this);
        root.setBackgroundColor(Color.rgb(237,240,244));
        root.setClipChildren(false);
        root.addView(web, new android.widget.FrameLayout.LayoutParams(-1, -1));
        dockHost = new GlassDockHost(this, root, (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0);
        dock = dockHost.dock;
        dock.setListener(page -> {
            if (destroyed) return;
            long request = ++dockRequest;
            web.evaluateJavascript("window.appDockNavigate && window.appDockNavigate(" + JSONObject.quote(page) + "," + request + ")", null);
        });
        setContentView(root);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            int left, top, right, bottom;
            if (Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets bars = insets.getInsets(
                    android.view.WindowInsets.Type.systemBars() | android.view.WindowInsets.Type.displayCutout());
                left = bars.left; top = bars.top; right = bars.right;
                bottom = Math.max(bars.bottom, insets.getInsets(android.view.WindowInsets.Type.ime()).bottom);
            } else {
                left = insets.getSystemWindowInsetLeft(); top = insets.getSystemWindowInsetTop();
                right = insets.getSystemWindowInsetRight();
                bottom = Math.min(insets.getSystemWindowInsetBottom(), insets.getStableInsetBottom());
                if (Build.VERSION.SDK_INT >= 28 && insets.getDisplayCutout() != null) {
                    android.view.DisplayCutout cutout = insets.getDisplayCutout();
                    left = Math.max(left, cutout.getSafeInsetLeft()); top = Math.max(top, cutout.getSafeInsetTop());
                    right = Math.max(right, cutout.getSafeInsetRight()); bottom = Math.max(bottom, cutout.getSafeInsetBottom());
                }
            }
            // Only content is inset at the top. The WebView's gradient continues
            // behind transparent status icons, including full-screen sheets.
            view.setPadding(left, 0, right, bottom);
            float nextTop = top / getResources().getDisplayMetrics().density;
            if (nextTop != statusBarInset) {
                statusBarInset = nextTop;
                web.evaluateJavascript("document.documentElement.style.setProperty('--native-safe-top','" + nextTop + "px')", null);
            }
            return insets.consumeSystemWindowInsets();
        });
        root.requestApplyInsets();
        if (Build.VERSION.SDK_INT >= 33) {
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, this::handleBack);
        }
        web.loadUrl(ORIGIN + "/index.html");
    }

    private static WebResourceResponse blocked() {
        return new WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden", new HashMap<>(), new ByteArrayInputStream(new byte[0]));
    }

    private final class Bridge {
        @JavascriptInterface public float statusBarInset() { return statusBarInset; }
        @JavascriptInterface public int dockVersion() { return 1; }
        @JavascriptInterface public boolean isDebugBuild() { return (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0; }
        @JavascriptInterface public void postMessage(String raw) {
            if (destroyed || raw == null || raw.length() > 2500000) return;
            final JSONObject message;
            final String id;
            final String action;
            try {
                message = new JSONObject(raw);
                id = message.getString("id");
                action = message.getString("action");
            } catch (Exception e) { sendBridgeReply("", false, "请求格式不正确"); return; }
            if (action.equals("dockState") || action.equals("dockDebug")) {
                runOnUiThread(() -> {
                    if (destroyed || dock == null) return;
                    try {
                        JSONObject payload = message.optJSONObject("payload");
                        if (payload == null) payload = new JSONObject();
                        if (action.equals("dockDebug")) {
                            if ((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0) throw new IOException("调试未启用");
                            if (payload.optBoolean("reset")) dock.resetTrace();
                            JSONObject diagnostics = dock.diagnostics().put("request", dockRequest);
                            if (payload.optBoolean("image")) diagnostics.put("backgroundPng", dock.debugBackdrop());
                            sendBridgeReply(id, true, diagnostics);
                            return;
                        }
                        String document = payload.optString("document");
                        if (dockDocument == null) dockDocument = document;
                        if (!document.equals(dockDocument)) { sendBridgeReply(id, true, new JSONObject().put("accepted", false)); return; }
                        boolean acceptPage = payload.optLong("request") >= dockRequest;
                        dockHost.applyState(payload.optString("page", "tasks"), payload.optBoolean("visible"), payload.optBoolean("dark"), payload.optBoolean("reduced"), acceptPage);
                        sendBridgeReply(id, true, new JSONObject().put("accepted", acceptPage));
                    } catch (Exception e) { sendBridgeReply(id, false, "无法更新底栏状态"); }
                });
                return;
            }
            if (action.equals("jdLogin") || action.equals("cancelJdLogin")) {
                runOnUiThread(() -> {
                    if (destroyed) return;
                    if (action.equals("cancelJdLogin")) {cancelJdLogin("cancelled");sendBridgeReply(id,true,cancelledPick("cancelled"));return;}
                    if(jdLoginRequest!=null){sendBridgeReply(id,false,"京东登录页已打开，请先完成或返回");return;}
                    jdLoginRequest=id;
                    try {
                        Intent login=new Intent(MainActivity.this,JdLoginActivity.class);
                        JSONObject payload=message.optJSONObject("payload");
                        if((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE)!=0 && payload!=null && payload.optBoolean("fixture"))login.putExtra("fixture",true);
                        startActivityForResult(login,JD_LOGIN_CODE);pickerHandler.postDelayed(jdLoginTimeout,590000L);
                    }catch(Exception e){jdLoginRequest=null;sendBridgeReply(id,false,"无法打开京东登录窗口，请使用粘贴 CK");}
                });
                return;
            }
            if (action.equals("haptic")) {
                runOnUiThread(() -> {
                    if (destroyed || web == null) return;
                    boolean performed = false;
                    long now = android.os.SystemClock.uptimeMillis();
                    if (getWindow().getDecorView().hasWindowFocus() && now - lastHapticAt >= 90) {
                        lastHapticAt = now;
                        int effect = Build.VERSION.SDK_INT >= 34
                            ? android.view.HapticFeedbackConstants.SEGMENT_FREQUENT_TICK
                            : android.view.HapticFeedbackConstants.CLOCK_TICK;
                        performed = web.performHapticFeedback(effect);
                    }
                    try { sendBridgeReply(id, true, new JSONObject().put("performed", performed)); }
                    catch (Exception ignored) { sendBridgeReply(id, true, new JSONObject()); }
                });
                return;
            }
            // File picking and explicit clipboard writes must not queue behind
            // a slow HTTP operation. All picker mappings are owned by the UI.
            if (action.equals("pickScript") || action.equals("cancelPickScript") || action.equals("copyText") || action.equals("readClipboardText") || action.equals("exportText")) {
                runOnUiThread(() -> {
                    if (destroyed) return;
                    if (action.equals("pickScript")) { beginScriptPick(id); return; }
                    if (action.equals("exportText")) { beginTextExport(id, message.optJSONObject("payload")); return; }
                    if (action.equals("cancelPickScript")) {
                        for (ScriptPick pick : new java.util.ArrayList<>(scriptPicks.values())) cancelScriptPick(pick, "cancelled");
                        sendBridgeReply(id, true, cancelledPick("cancelled")); return;
                    }
                    if (action.equals("readClipboardText")) {
                        try {
                            if (!getWindow().getDecorView().hasWindowFocus()) throw new IOException("请在 App 前台读取剪贴板");
                            ClipboardManager manager = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                            ClipData clip = manager == null ? null : manager.getPrimaryClip();
                            CharSequence value = clip != null && clip.getItemCount() > 0 ? clip.getItemAt(0).getText() : null;
                            String text = value == null ? "" : value.toString();
                            if (text.getBytes(StandardCharsets.UTF_8).length > ScriptImportReader.MAX_BYTES) throw new IOException("剪贴板文本超过 1 MiB");
                            sendBridgeReply(id, true, new JSONObject().put("text", text));
                        } catch (Exception e) { sendBridgeReply(id, false, "无法读取剪贴板，请手动粘贴不超过 1 MiB 的文本"); }
                        return;
                    }
                    try {
                        JSONObject payload = message.optJSONObject("payload");
                        Object value = payload == null ? null : payload.opt("text");
                        if (!(value instanceof String)) throw new IOException("没有可复制的文本");
                        String text = (String) value;
                        if (text.getBytes(StandardCharsets.UTF_8).length > ScriptImportReader.MAX_BYTES)
                            throw new IOException("复制内容超过 1 MiB，无法写入剪贴板");
                        ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                        if (clipboard == null) throw new IOException("当前设备无法使用剪贴板");
                        ClipData clip = ClipData.newPlainText("青龙文本", text);
                        PersistableBundle extras = new PersistableBundle();
                        extras.putBoolean("android.content.extra.IS_SENSITIVE", true);
                        clip.getDescription().setExtras(extras);
                        clipboard.setPrimaryClip(clip);
                        sendBridgeReply(id, true, new JSONObject().put("copied", true));
                    } catch (Exception e) { sendBridgeReply(id, false, readableError(e)); }
                });
                return;
            }
            try { worker.execute(() -> {
                if (destroyed) return;
                try {
                    Object result = dispatch(action, message.optJSONObject("payload"));
                    sendBridgeReply(id, true, result);
                } catch (Exception e) {
                    sendBridgeReply(id, false, e);
                }
            }); } catch (RejectedExecutionException ignored) {
                // onDestroy may stop the executor while an already-dispatched
                // WebView bridge invocation is entering this method.
            }
        }
    }

    private void sendBridgeReply(String id, boolean ok, Object value) {
        try {
            JSONObject response = new JSONObject().put("ok", ok);
            response.put(ok ? "data" : "error", !ok && value instanceof Exception ? readableError((Exception)value) : value == null ? JSONObject.NULL : value);
            if (!ok && value instanceof QinglongApi.ApiException) {
                QinglongApi.ApiException error = (QinglongApi.ApiException)value;
                response.put("errorInfo", new JSONObject().put("httpStatus", error.httpStatus).put("apiCode", error.apiCode).put("permissionDenied", error.permissionDenied));
            }
            final String script = ("typeof window.appReceive === 'function' && window.appReceive(" + JSONObject.quote(id) + "," + response + ")")
                .replace("\u2028", "\\u2028").replace("\u2029", "\\u2029");
            runOnUiThread(() -> { if (!destroyed && web != null) web.evaluateJavascript(script, null); });
        } catch (Exception ignored) { /* Never log data returned by the bridge. */ }
    }

    private void cancelJdLogin(String reason) {
        if(jdLoginRequest==null)return;String request=jdLoginRequest;jdLoginRequest=null;
        pickerHandler.removeCallbacks(jdLoginTimeout);
        try{finishActivity(JD_LOGIN_CODE);}catch(Exception ignored){}
        sendBridgeReply(request,true,cancelledPick(reason));
    }

    private static JSONObject cancelledPick(String reason) {
        try { return new JSONObject().put("cancelled", true).put("reason", reason); }
        catch (Exception impossible) { throw new AssertionError(impossible); }
    }

    private void beginScriptPick(String id) {
        if (!scriptPicks.isEmpty()) {
            sendBridgeReply(id, false, "文件选择器已打开，请完成选择或取消后重试"); return;
        }
        int code = NEXT_PICK_CODE.getAndUpdate(previous -> previous >= 0x7FFE ? 0x4A00 : previous + 1);
        ScriptPick pick = new ScriptPick(code, id);
        pick.timeout = () -> cancelScriptPick(pick, "timeout");
        scriptPicks.put(code, pick);
        try {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false);
            pickerHandler.postDelayed(pick.timeout, PICK_TIMEOUT_MS);
            startActivityForResult(intent, code);
        } catch (Exception e) {
            finishScriptPick(pick, false, "无法打开系统文件选择器，请确认设备安装了文件管理器");
        }
    }

    private void beginTextExport(String id, JSONObject payload) {
        if (!scriptPicks.isEmpty()) { sendBridgeReply(id, false, "文件选择器已打开，请先完成或取消"); return; }
        try {
            String name = payload.getString("filename");
            if (name.isEmpty() || name.length() > 200 || name.equals(".") || name.equals("..") || name.matches(".*[\\\\/\\x00-\\x1f].*"))
                throw new IOException("导出文件名无效");
            byte[] output = payload.getString("content").getBytes(StandardCharsets.UTF_8);
            if (output.length > 2 * 1024 * 1024) throw new IOException("导出文本超过 2 MiB，请使用网页面板处理");
            int code = NEXT_PICK_CODE.getAndUpdate(previous -> previous >= 0x7FFE ? 0x4A00 : previous + 1);
            ScriptPick pick = new ScriptPick(code, id); pick.output = output;
            pick.timeout = () -> cancelScriptPick(pick, "timeout"); scriptPicks.put(code, pick);
            Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                .setType(name.endsWith(".json") ? "application/json" : "application/octet-stream").putExtra(Intent.EXTRA_TITLE, name);
            pickerHandler.postDelayed(pick.timeout, PICK_TIMEOUT_MS);
            try { startActivityForResult(intent, code); }
            catch (Exception e) { finishScriptPick(pick, false, "无法打开系统保存窗口"); }
        } catch (Exception e) { sendBridgeReply(id, false, "无法导出，请检查文件名与文本大小"); }
    }

    private void cancelScriptPick(ScriptPick pick, String reason) {
        if (!pick.active) return;
        pick.signal.cancel();
        if (pick.readTask != null) pick.readTask.cancel(true);
        try { finishActivity(pick.code); } catch (Exception ignored) {}
        finishScriptPick(pick, true, cancelledPick(reason));
    }

    private void finishScriptPick(ScriptPick pick, boolean ok, Object result) {
        if (!pick.active || scriptPicks.get(pick.code) != pick) return;
        pick.active = false;
        scriptPicks.remove(pick.code);
        pickerHandler.removeCallbacks(pick.timeout);
        sendBridgeReply(pick.id, ok, result);
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if(requestCode==JD_LOGIN_CODE){
            String request=jdLoginRequest;jdLoginRequest=null;pickerHandler.removeCallbacks(jdLoginTimeout);if(request==null)return;
            String cookie=resultCode==RESULT_OK&&data!=null?JdSessionRules.webCookie(data.getStringExtra("cookie")):null;
            try{sendBridgeReply(request,true,cookie==null?cancelledPick("cancelled"):new JSONObject().put("cookie",cookie));}catch(Exception ignored){sendBridgeReply(request,false,"未取得完整的网页 CK");}
            return;
        }
        ScriptPick pick = scriptPicks.get(requestCode);
        // Results from an Activity/WebView destroyed while the picker was open
        // are intentionally ignored; its request ID belongs to the old page.
        if (pick == null || !pick.active || destroyed) return;
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            finishScriptPick(pick, true, cancelledPick("cancelled")); return;
        }
        Uri uri = data.getData();
        if (!"content".equals(uri.getScheme())) {
            finishScriptPick(pick, false, "请选择系统文件提供者中的文件"); return;
        }
        try {
            pick.readTask = fileWorker.submit(() -> {
                Object result;
                boolean ok;
                try {
                    if (pick.output != null) {
                        if (!pick.active || destroyed) throw new IOException("保存已取消");
                        try (java.io.OutputStream output = getContentResolver().openOutputStream(uri, "wt")) {
                            if (output == null) throw new IOException("无法写入所选位置");
                            output.write(pick.output);
                        }
                        result = new JSONObject().put("cancelled", false).put("saved", true).put("sizeBytes", pick.output.length);
                    } else {
                        ScriptImportReader.Document document = readSelectedScript(uri, pick);
                        result = new JSONObject().put("cancelled", false).put("filename", document.filename)
                            .put("content", document.content).put("sizeBytes", document.sizeBytes).put("encoding", "UTF-8");
                    }
                    ok = true;
                } catch (Exception e) {
                    result = pick.output != null ? "保存文件失败，请重新选择保存位置" : e instanceof IOException ? readableError(e) : "无法读取所选文件，请重新选择已下载到本机的文件";
                    ok = false;
                }
                final Object response = result;
                final boolean success = ok;
                runOnUiThread(() -> { if (!destroyed) finishScriptPick(pick, success, response); });
            });
        } catch (RejectedExecutionException e) {
            finishScriptPick(pick, false, "已有文件正在读取，请稍后重试或选择已下载到本机的文件");
        }
    }

    private ScriptImportReader.Document readSelectedScript(Uri uri, ScriptPick pick) throws IOException {
        String name = null;
        long reportedSize = -1;
        try (Cursor cursor = getContentResolver().query(uri,
                new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}, null, null, null, pick.signal)) {
            if (cursor != null && cursor.moveToFirst()) {
                int nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                int sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE);
                if (nameColumn >= 0 && !cursor.isNull(nameColumn)) name = cursor.getString(nameColumn);
                if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) reportedSize = cursor.getLong(sizeColumn);
            }
        } catch (Exception e) { throw new IOException("无法读取文件信息，请重新选择已下载到本机的文件"); }
        ScriptImportReader.validateFilename(name);
        if (reportedSize > ScriptImportReader.MAX_BYTES) throw new IOException("本地文件超过 1 MiB，请使用网页面板处理");
        AssetFileDescriptor descriptor;
        try { descriptor = getContentResolver().openAssetFileDescriptor(uri, "r", pick.signal); }
        catch (Exception e) { throw new IOException("无法打开所选文件，请重新选择已下载到本机的文件"); }
        if (descriptor == null) throw new IOException("无法打开所选文件，请重新选择");
        try (AssetFileDescriptor selected = descriptor; InputStream input = selected.createInputStream()) {
            if (!pick.active || destroyed) throw new IOException("文件读取已取消");
            return ScriptImportReader.read(input, name);
        }
    }

    private static final class ScriptPick {
        final int code;
        final String id;
        final CancellationSignal signal = new CancellationSignal();
        volatile boolean active = true;
        Future<?> readTask;
        byte[] output;
        Runnable timeout;
        ScriptPick(int code, String id) { this.code = code; this.id = id; }
    }

    private static String readableError(Exception e) {
        if (e instanceof javax.net.ssl.SSLException) return "HTTPS 证书校验失败。请为面板配置有效证书，App 不会绕过证书验证。";
        if (e instanceof java.net.SocketTimeoutException) return "连接超时，请检查面板地址、端口和手机网络。";
        if (e instanceof java.net.UnknownHostException) return "无法解析面板域名，请检查地址或 DNS。";
        if (e instanceof java.net.ConnectException) return "无法连接面板，请检查服务是否在线以及端口是否开放。";
        String message = e.getMessage();
        return message == null ? "操作失败，请稍后重试。" : message;
    }

    private JSONObject profile(JSONObject vault, String id) throws Exception {
        JSONArray list = vault.getJSONArray("servers");
        for (int i = 0; i < list.length(); i++) if (list.getJSONObject(i).optString("id").equals(id)) return list.getJSONObject(i);
        throw new Exception("未找到面板，请重新选择。");
    }

    private JSONObject publicState(JSONObject vault) throws Exception {
        JSONObject result = new JSONObject().put("activeId", vault.optString("activeId")).put("version", "0.17.0");
        JSONArray list = new JSONArray();
        JSONArray full = vault.getJSONArray("servers");
        for (int i = 0; i < full.length(); i++) {
            JSONObject p = full.getJSONObject(i);
            list.put(new JSONObject().put("id", p.getString("id")).put("name", p.getString("name"))
                .put("url", p.getString("url")).put("clientId", p.optString("clientId"))
                .put("authMode", p.optString("authMode", "application")).put("username", p.optString("username"))
                .put("requiresLogin", "password".equals(p.optString("authMode")) && p.optString("sessionToken").isEmpty())
                .put("allowHttp", p.optBoolean("allowHttp")).put("hasSecret", !p.optString("clientSecret").isEmpty()));
        }
        return result.put("servers", list);
    }

    private QinglongApi client(JSONObject p) {
        String id = p.optString("id");
        if (!clients.containsKey(id)) clients.put(id, "password".equals(p.optString("authMode"))
            ? QinglongApi.userSession(p.optString("url"), p.optString("username"), p.optString("sessionToken"))
            : new QinglongApi(p.optString("url"), p.optString("clientId"), p.optString("clientSecret")));
        return clients.get(id);
    }

    private Object dispatch(String action, JSONObject payload) throws Exception {
        ensureAlive();
        if (payload == null) payload = new JSONObject();
        JSONObject vault = store.read();
        switch (action) {
            case "bootstrap": return publicState(vault).put("pickerInterrupted", pickerInterrupted);
            case "fetchText": {
                ScriptImportReader.Document doc = RemoteScriptReader.read(payload.getString("url"), payload.getString("filename"), payload.optBoolean("allowHttp"), payload.optString("kind").equals("configs"));
                return new JSONObject().put("filename", doc.filename).put("content", doc.content).put("sizeBytes", doc.sizeBytes).put("encoding", "UTF-8").put("cancelled", false);
            }
            case "reorderServers": {
                JSONArray ids = payload.getJSONArray("ids");
                JSONObject updated = store.update(current -> {
                    JSONArray old = current.getJSONArray("servers"), sorted = new JSONArray();
                    if (ids.length() != old.length()) throw new IOException("连接数量已变化，请刷新后重试");
                    java.util.HashSet<String> seen = new java.util.HashSet<>();
                    for (int i = 0; i < ids.length(); i++) {
                        String id = ids.getString(i); if (!seen.add(id)) throw new IOException("连接排序无效");
                        sorted.put(profile(current, id));
                    }
                    current.put("servers", sorted);
                });
                return publicState(updated);
            }
            case "appearance": {
                final boolean dark = payload.optBoolean("dark");
                runOnUiThread(() -> {
                    applySystemBars(dark);
                    web.setBackgroundColor(dark ? Color.rgb(20,24,32) : Color.rgb(237,240,244));
                    if (web.getParent() instanceof android.view.View) ((android.view.View)web.getParent()).setBackgroundColor(dark ? Color.rgb(20,24,32) : Color.rgb(237,240,244));
                });
                return new JSONObject();
            }
            case "saveServer": {
                String id = payload.optString("id");
                JSONObject previous = id.isEmpty() ? null : profile(vault, id);
                String url = payload.optString("url").trim().replaceAll("/+$", "");
                URI uri;
                try { uri = new URI(url); } catch (Exception e) { throw new Exception("面板地址格式不正确。"); }
                if (!("https".equals(uri.getScheme()) || "http".equals(uri.getScheme())) || uri.getHost() == null ||
                    uri.getRawUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null)
                    throw new Exception("请输入完整 http:// 或 https:// 面板地址，不含账号、查询参数或 #。");
                if ("http".equals(uri.getScheme()) && !payload.optBoolean("allowHttp"))
                    throw new Exception("HTTP 会明文传输登录信息，请先勾选允许 HTTP 或改用 HTTPS。");
                String mode = payload.optString("authMode", "password");
                if ("password".equals(mode)) {
                    String username = payload.optString("username").trim();
                    String password = payload.optString("password");
                    String name = payload.optString("name").trim();
                    if (name.isEmpty() || username.isEmpty()) throw new Exception("请填写面板名称和账号。");
                    QinglongApi api;
                    if (password.isEmpty() && previous != null && "password".equals(previous.optString("authMode"))
                        && url.equals(previous.optString("url")) && username.equals(previous.optString("username")) && !previous.optString("sessionToken").isEmpty()) {
                        api = QinglongApi.userSession(url, username, previous.optString("sessionToken"));
                        api.request("GET", "/user");
                    } else {
                        try { api = QinglongApi.loginUser(url, username, password, payload.optString("code")); }
                        catch (QinglongApi.TwoFactorRequired e) { return new JSONObject().put("requiresTwoFactor", true); }
                    }
                    if (id.isEmpty()) id = UUID.randomUUID().toString();
                    final String savedId = id;
                    final boolean editing = previous != null;
                    JSONObject saved = new JSONObject().put("id", id).put("name", name).put("url", url)
                        .put("authMode", "password").put("username", username).put("sessionToken", api.sessionToken())
                        .put("allowHttp", payload.optBoolean("allowHttp"));
                    JSONObject updated = store.update(current -> {
                        ensureAlive(); if (editing) profile(current, savedId);
                        JSONArray old = current.getJSONArray("servers"), next = new JSONArray();
                        for (int i = 0; i < old.length(); i++) if (!old.getJSONObject(i).optString("id").equals(savedId)) next.put(old.getJSONObject(i));
                        next.put(saved); current.put("servers", next).put("activeId", savedId);
                    });
                    clients.put(id, api); return publicState(updated);
                }
                if (!"application".equals(mode)) throw new Exception("不支持的登录方式。");
                String secret = payload.optString("clientSecret").trim();
                if (secret.isEmpty() && previous != null) secret = previous.optString("clientSecret");
                String clientId = payload.optString("clientId").trim();
                String name = payload.optString("name").trim();
                if (name.isEmpty() || clientId.isEmpty() || secret.isEmpty()) throw new Exception("请填写面板名称、Client ID 和 Client Secret。");
                if (id.isEmpty()) id = UUID.randomUUID().toString();
                JSONObject saved = new JSONObject().put("id", id).put("name", name).put("url", url)
                    .put("authMode", "application").put("clientId", clientId).put("clientSecret", secret).put("allowHttp", payload.optBoolean("allowHttp"));
                QinglongApi api = new QinglongApi(url, clientId, secret);
                api.authenticate();
                final String savedId = id;
                final boolean editing = previous != null;
                JSONObject updated = store.update(current -> {
                    ensureAlive();
                    // A panel removed while authentication was pending must not
                    // be resurrected by an older edit operation.
                    if (editing) profile(current, savedId);
                    JSONArray old = current.getJSONArray("servers"), next = new JSONArray();
                    for (int i = 0; i < old.length(); i++) {
                        if (!old.getJSONObject(i).getString("id").equals(savedId)) next.put(old.getJSONObject(i));
                    }
                    next.put(saved);
                    current.put("servers", next).put("activeId", savedId);
                });
                clients.put(id, api);
                return publicState(updated);
            }
            case "selectServer": {
                String id = payload.getString("id"); profile(vault, id);
                JSONObject updated = store.update(current -> {
                    ensureAlive(); profile(current, id); current.put("activeId", id);
                });
                return publicState(updated);
            }
            case "logoutServer": {
                String id = payload.getString("id");
                JSONObject p = profile(vault, id);
                if ("password".equals(p.optString("authMode")) && !p.optString("sessionToken").isEmpty()) {
                    try { client(p).request("POST", "/user/logout"); }
                    catch (java.io.IOException e) { /* Always permit removing a stale local session. */ }
                }
                JSONObject updated = store.update(current -> { ensureAlive(); profile(current, id).remove("sessionToken"); });
                clients.remove(id); return publicState(updated);
            }
            case "deleteServer": {
                String id = payload.getString("id");
                JSONObject updated = store.update(current -> {
                    ensureAlive();
                    JSONArray old = current.getJSONArray("servers"), next = new JSONArray();
                    for (int i = 0; i < old.length(); i++) {
                        if (!old.getJSONObject(i).getString("id").equals(id)) next.put(old.getJSONObject(i));
                    }
                    current.put("servers", next);
                    if (current.optString("activeId").equals(id)) {
                        current.put("activeId", next.length() == 0 ? "" : next.getJSONObject(0).getString("id"));
                    }
                });
                clients.remove(id); return publicState(updated);
            }
            case "request": {
                JSONObject p = profile(vault, payload.getString("serverId"));
                String path = payload.getString("path");
                // QinglongApi validates the decoded URI path separately from
                // the query, so search/file values such as api..js remain valid.
                if (!path.startsWith("/") || path.startsWith("//")) throw new Exception("不支持的接口路径。");
                String method = payload.optString("method", "GET");
                if (!(method.equals("GET") || method.equals("POST") || method.equals("PUT") || method.equals("DELETE"))) throw new Exception("不支持的请求方法。");
                Object body = payload.opt("body");
                try { return client(p).request(method, path, body == JSONObject.NULL ? null : body); }
                catch (QinglongApi.ApiException e) {
                    if ("password".equals(p.optString("authMode")) && !e.permissionDenied && (e.httpStatus == 401 || e.apiCode == 401)) {
                        final String expiredId = p.getString("id");
                        store.update(current -> { ensureAlive(); profile(current, expiredId).remove("sessionToken"); });
                    }
                    throw e;
                }
            }
            default: throw new Exception("不支持的操作。");
        }
    }

    private void ensureAlive() throws java.io.IOException {
        if (destroyed || Thread.currentThread().isInterrupted()) {
            throw new java.io.IOException("页面已关闭，请重新打开后重试。");
        }
    }

    private void handleBack() {
        if (destroyed || isFinishing()) return;
        if (web == null) { finish(); return; }
        web.evaluateJavascript(
            "(function(){try{return !!(window.appBack && window.appBack());}catch(e){return false;}})()",
            consumed -> { if (!"true".equals(consumed) && !destroyed && !isFinishing()) finish(); });
    }

    @Override public void onBackPressed() { handleBack(); }
    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putBoolean("scriptPickerInterrupted", !scriptPicks.isEmpty());
        super.onSaveInstanceState(outState);
    }
    @Override protected void onPause() {
        if (dockHost != null) dockHost.pause();
        super.onPause();
    }
    @Override protected void onResume() {
        super.onResume();
        if (dockHost != null) dockHost.resume();
    }
    @Override protected void onDestroy() {
        cancelJdLogin("cancelled");
        if (dockHost != null) dockHost.dispose();
        // A commit already inside the transaction completes before destruction;
        // later operations see destroyed and cannot write an obsolete snapshot.
        synchronized (ProfileStore.TRANSACTION_LOCK) { destroyed = true; }
        for (ScriptPick pick : new java.util.ArrayList<>(scriptPicks.values())) cancelScriptPick(pick, "cancelled");
        fileWorker.shutdownNow();
        worker.shutdownNow();
        if (web != null) { web.removeJavascriptInterface("NativeBridge"); web.destroy(); web = null; }
        super.onDestroy();
    }
}
