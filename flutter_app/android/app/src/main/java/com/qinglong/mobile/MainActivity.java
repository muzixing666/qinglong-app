package com.qinglong.mobile;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.android.RenderMode;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
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


public final class MainActivity extends FlutterActivity {
    private GlassDockView dock;
    private GlassDockHost dockHost;
    private long dockRequest;
    private String dockDocument;
    private MethodChannel channel;
    private final HashMap<String,MethodChannel.Result> replies=new HashMap<>();
    private CodeEditorFactory editors;
    private String shortcutPage, startupShortcut;
    private android.widget.Toast feedbackToast;
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
        window.setNavigationBarColor(dark ? Color.rgb(20,20,22) : Color.rgb(239,237,240));
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


    @Override public RenderMode getRenderMode() { return RenderMode.texture; }
    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        store=new ProfileStore(this);
        channel=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"qinglong/native");
        editors=new CodeEditorFactory(this);
        engine.getPlatformViewsController().getRegistry().registerViewFactory("ql-code-editor",editors);
        channel.setMethodCallHandler((call,result)->{
            try {
                if(call.method.equals("toast")){
                    if(feedbackToast!=null)feedbackToast.cancel();
                    feedbackToast=android.widget.Toast.makeText(this,(String)call.arguments,android.widget.Toast.LENGTH_SHORT);feedbackToast.show();result.success(null);return;
                }
                if(call.method.equals("consumeShortcut")){String page=shortcutPage;shortcutPage=null;if(getIntent()!=null)getIntent().removeExtra("shortcut_page");result.success(page);return;}
                if(call.method.equals("widgetState")){
                    JSONObject data=new JSONObject((java.util.Map)call.arguments);
                    worker.execute(()->{try{
                        if(data.optString("serverId").equals(store.read().optString("activeId"))){
                            JSONObject previous=PanelWidgetProvider.snapshot(this);
                            if((data.optInt("total",-1)<0||data.optLong("updated")<previous.optLong("updated"))&&data.optString("serverId").equals(previous.optString("serverId"))&&previous.optInt("total",-1)>=0){previous.put("panel",data.optString("panel"));PanelWidgetProvider.publish(this,previous);}
                            else PanelWidgetProvider.publish(this,data);
                        }
                    }catch(Exception ignored){}});
                    result.success(null);return;
                }
                if(call.method.equals("desktopCapabilities")){
                    HashMap<String,Object> info=new HashMap<>();
                    info.put("shortcuts",getSystemService(android.content.pm.ShortcutManager.class).getManifestShortcuts().size());
                    info.put("pinSupported",android.appwidget.AppWidgetManager.getInstance(this).isRequestPinAppWidgetSupported());
                    info.put("widgets",android.appwidget.AppWidgetManager.getInstance(this).getAppWidgetIds(new android.content.ComponentName(this,PanelWidgetProvider.class)).length);
                    result.success(info);return;
                }
                if(call.method.equals("pinWidget")){
                    android.appwidget.AppWidgetManager wm=android.appwidget.AppWidgetManager.getInstance(this);
                    result.success(wm.isRequestPinAppWidgetSupported()&&wm.requestPinAppWidget(new android.content.ComponentName(this,PanelWidgetProvider.class),null,null));return;
                }
                if(call.method.equals("editorRecovery")){editors.recovery(call.arguments,result);return;}
                if(call.method.equals("editorGet")){editors.getText(call.arguments,result);return;}
                if(call.method.equals("editorWarm")){editors.warm();result.success(null);return;}
                if(call.method.equals("editorReady")){editors.isReady(call.arguments,result);return;}
                if(call.method.equals("openExternal")){
                    android.net.Uri uri=android.net.Uri.parse((String)call.arguments);
                    if(!"https".equals(uri.getScheme())||!"github.com".equals(uri.getHost())){result.error("URL","无效下载地址",null);return;}
                    try{startActivity(new android.content.Intent(android.content.Intent.ACTION_VIEW,uri));result.success(null);}
                    catch(Exception e){result.error("URL","没有可以打开此链接的浏览器，请复制地址",null);}return;
                }
                if(call.method.equals("editorInsert")){editors.insert(call.arguments);result.success(null);return;}
                if(call.method.equals("editorAction")){editors.action(call.arguments);result.success(null);return;}
                if(!call.method.equals("call")){result.notImplemented();return;}
                JSONObject message=new JSONObject((String)call.arguments);
                String id=UUID.randomUUID().toString(); message.put("id",id); replies.put(id,result);
                if(message.optString("action").equals("dockSample")){
                    if(dockHost!=null)dockHost.requestSample();sendBridgeReply(id,true,new JSONObject());return;
                }
                if(message.optString("action").equals("forecastTasks")){
                    worker.execute(()->{try{sendBridgeReply(id,true,CronForecast.batch(message.optJSONObject("payload")));}
                      catch(Exception error){sendBridgeReply(id,false,"无法计算下次运行时间");}});return;
                }
                if(message.optString("action").equals("dockFrameReady")){
                    JSONObject payload=message.optJSONObject("payload");
                    if(dockHost!=null && payload!=null && payload.optString("document").equals(dockDocument) && payload.optLong("request")>=dockRequest)
                        dockHost.pageFrameReady(payload.optString("page"));
                    sendBridgeReply(id,true,new JSONObject());return;
                }
                new Bridge().postMessage(message.toString());
            }catch(Exception e){result.error("NATIVE","请求格式不正确",null);}
        });
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        shortcutPage=getIntent().getStringExtra("shortcut_page");startupShortcut=shortcutPage;
        applySystemBars(getSharedPreferences("flutter_appearance",0).getBoolean("dark",false));
        WebView.setWebContentsDebuggingEnabled((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE)!=0);
        android.view.View root=findViewById(android.R.id.content);
        dockHost=new GlassDockHost(this,root,(getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE)!=0);
        dockHost.synchronizeWithFrames();
        dock=dockHost.dock;
        dock.setListener(page->{
            if(destroyed)return; long request=++dockRequest;
            HashMap<String,Object> args=new HashMap<>();args.put("page",page);args.put("request",request);
            channel.invokeMethod("dockNavigate",args);
        });
        root.setOnApplyWindowInsetsListener((view,insets)->{
            int bottom=Build.VERSION.SDK_INT>=30?insets.getInsets(android.view.WindowInsets.Type.systemBars()).bottom:Math.min(insets.getStableInsetBottom(),insets.getSystemWindowInsetBottom());
            dockHost.setBottomInset(bottom);return insets;
        });root.requestApplyInsets();
    }
    @Override public void onNewIntent(android.content.Intent intent){
        super.onNewIntent(intent);setIntent(intent);shortcutPage=intent.getStringExtra("shortcut_page");
        if(shortcutPage!=null&&channel!=null)channel.invokeMethod("shortcutNavigate",null);
    }
    private void sendBridgeReply(String id,boolean ok,Object value){
        try{
            JSONObject packet=new JSONObject().put("ok",ok).put(ok?"data":"error", !ok&&value instanceof Exception?readableError((Exception)value):value==null?JSONObject.NULL:value);
            if(!ok&&value instanceof QinglongApi.ApiException){QinglongApi.ApiException e=(QinglongApi.ApiException)value;packet.put("errorInfo",new JSONObject().put("httpStatus",e.httpStatus).put("apiCode",e.apiCode).put("permissionDenied",e.permissionDenied));}
            runOnUiThread(()->{MethodChannel.Result result=replies.remove(id);if(result!=null&&!destroyed)result.success(packet.toString());});
        }catch(Exception ignored){}
    }
    private final class Bridge {
        
        
        
        public void postMessage(String raw) {
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
                            JSONObject diagnostics = dock.diagnostics().put("request", dockRequest).put("backgroundPage",dockHost.backdropPage()).put("awaitingFrame",dockHost.awaitingFrame()).put("discardedCopies",dockHost.discardedCopies());
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
                    if (destroyed || getWindow() == null) return;
                    boolean performed = false;
                    long now = android.os.SystemClock.uptimeMillis();
                    if (getWindow().getDecorView().hasWindowFocus() && now - lastHapticAt >= 90) {
                        lastHapticAt = now;
                        int effect = Build.VERSION.SDK_INT >= 34
                            ? android.view.HapticFeedbackConstants.SEGMENT_FREQUENT_TICK
                            : android.view.HapticFeedbackConstants.CLOCK_TICK;
                        performed = getWindow().getDecorView().performHapticFeedback(effect);
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
        JSONObject result = new JSONObject().put("activeId", vault.optString("activeId")).put("version", "0.22.0");
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
            case "bootstrap": return publicState(vault).put("pickerInterrupted", pickerInterrupted).put("nativeDock",true).put("shortcutPage",startupShortcut==null?"":startupShortcut).put("dark",getSharedPreferences("flutter_appearance",0).getBoolean("dark",false)).put("textScale",getSharedPreferences("flutter_appearance",0).getFloat("textScale",1f));
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
                boolean dark=payload.optBoolean("dark");
                getSharedPreferences("flutter_appearance",0).edit().putBoolean("dark",dark).putFloat("textScale",(float)payload.optDouble("textScale",getSharedPreferences("flutter_appearance",0).getFloat("textScale",1f))).apply();
                runOnUiThread(() -> applySystemBars(dark));PanelWidgetProvider.renderAll(this); return new JSONObject();
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


    @Override protected void onPause(){if(dockHost!=null)dockHost.pause();super.onPause();}
    @Override protected void onResume(){super.onResume();if(dockHost!=null)dockHost.resume();}
    @Override protected void onDestroy(){
        if(editors!=null)editors.disposeWarm();
        cancelJdLogin("cancelled");
        for(ScriptPick pick:new java.util.ArrayList<>(scriptPicks.values()))cancelScriptPick(pick,"cancelled");
        if(dockHost!=null)dockHost.dispose();
        synchronized(ProfileStore.TRANSACTION_LOCK){destroyed=true;}
        fileWorker.shutdownNow();worker.shutdownNow();replies.clear();super.onDestroy();
    }
}
