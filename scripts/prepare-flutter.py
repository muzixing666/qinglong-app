"""Sync the reviewed Android services; Flutter owns all management UI."""
from pathlib import Path
import shutil
root=Path(__file__).resolve().parent.parent
app=root/'flutter_app'
java=app/'android/app/src/main/java/com/qinglong/mobile'
java.mkdir(parents=True,exist_ok=True)
old=root/'app/src/main/java/com/qinglong/mobile'
for name in ['ProfileStore','QinglongApi','ScriptImportReader','RemoteScriptReader','JdSessionRules','JdLoginActivity','GlassDockView','GlassDockHost','CronForecast']:
    shutil.copyfile(old/(name+'.java'),java/(name+'.java'))
p=java/'GlassDockHost.java'
s=p.read_text(encoding='utf-8').replace('private int epoch;', 'private int epoch;\n    private int bottomInset;\n    void setBottomInset(int value) { bottomInset=value; if(wanted) show(); }')
s=s.replace('root.getPaddingBottom()', '(root.getPaddingBottom()+bottomInset)')
p.write_text(s,encoding='utf-8')
source=(old/'MainActivity.java').read_text(encoding='utf-8')
imports=source[source.index('import android.app.Activity;'):source.index('/** The UI')]
fields=source[source.index('    private ProfileStore store;'):source.index('    private void applySystemBars')]
bars=source[source.index('    private void applySystemBars'):source.index('    @Override public void onCreate')]
bars=bars.replace('Color.rgb(20,24,32)', 'Color.rgb(20,20,22)').replace('Color.rgb(237,240,244)', 'Color.rgb(239,237,240)')
bridge=source[source.index('    private final class Bridge'):source.index('    private void sendBridgeReply')]
bridge=bridge.replace('@JavascriptInterface public float statusBarInset() { return statusBarInset; }','').replace('@JavascriptInterface public int dockVersion() { return 1; }','').replace('@JavascriptInterface public boolean isDebugBuild() { return (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0; }','')
bridge=bridge.replace('@JavascriptInterface public void postMessage','public void postMessage').replace('web == null','getWindow() == null').replace('web.performHapticFeedback','getWindow().getDecorView().performHapticFeedback')
helpers=source[source.index('    private void cancelJdLogin'):source.index('    private void handleBack')]
start=helpers.index('            case "appearance":')
end=helpers.index('            case "saveServer":',start)
helpers=helpers[:start]+'''            case "appearance": {
                boolean dark=payload.optBoolean("dark");
                getSharedPreferences("flutter_appearance",0).edit().putBoolean("dark",dark).putFloat("textScale",(float)payload.optDouble("textScale",getSharedPreferences("flutter_appearance",0).getFloat("textScale",1f))).apply();
                runOnUiThread(() -> applySystemBars(dark)); return new JSONObject();
            }
'''+helpers[end:]
version=(app/'pubspec.yaml').read_text(encoding='utf-8').split('version: ',1)[1].split('+',1)[0].strip()
helpers=helpers.replace('"0.17.0"','"'+version+'"').replace('return publicState(vault).put("pickerInterrupted", pickerInterrupted);','return publicState(vault).put("pickerInterrupted", pickerInterrupted).put("nativeDock",true).put("dark",getSharedPreferences("flutter_appearance",0).getBoolean("dark",false));')
bridge=bridge.replace('dock.diagnostics().put("request", dockRequest)', 'dock.diagnostics().put("request", dockRequest).put("backgroundPage",dockHost.backdropPage()).put("awaitingFrame",dockHost.awaitingFrame()).put("discardedCopies",dockHost.discardedCopies())')
helpers=helpers.replace('.put("dark",getSharedPreferences("flutter_appearance",0).getBoolean("dark",false));','.put("dark",getSharedPreferences("flutter_appearance",0).getBoolean("dark",false)).put("textScale",getSharedPreferences("flutter_appearance",0).getFloat("textScale",1f));')
prefix='''package com.qinglong.mobile;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.android.RenderMode;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
'''+imports+'''
public final class MainActivity extends FlutterActivity {
    private GlassDockView dock;
    private GlassDockHost dockHost;
    private long dockRequest;
    private String dockDocument;
    private MethodChannel channel;
    private final HashMap<String,MethodChannel.Result> replies=new HashMap<>();
    private CodeEditorFactory editors;
'''+fields+bars+'''
    @Override public RenderMode getRenderMode() { return RenderMode.texture; }
    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        store=new ProfileStore(this);
        channel=new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"qinglong/native");
        editors=new CodeEditorFactory(this);
        engine.getPlatformViewsController().getRegistry().registerViewFactory("ql-code-editor",editors);
        channel.setMethodCallHandler((call,result)->{
            try {
                if(call.method.equals("editorGet")){editors.getText(result);return;}
                if(call.method.equals("editorWarm")){editors.warm();result.success(null);return;}
                if(call.method.equals("editorReady")){editors.isReady(result);return;}
                if(call.method.equals("openExternal")){
                    android.net.Uri uri=android.net.Uri.parse((String)call.arguments);
                    if(!"https".equals(uri.getScheme())||!"github.com".equals(uri.getHost())){result.error("URL","无效下载地址",null);return;}
                    try{startActivity(new android.content.Intent(android.content.Intent.ACTION_VIEW,uri));result.success(null);}
                    catch(Exception e){result.error("URL","没有可以打开此链接的浏览器，请复制地址",null);}return;
                }
                if(call.method.equals("editorInsert")){editors.insert((String)call.arguments);result.success(null);return;}
                if(call.method.equals("editorAction")){editors.action((String)call.arguments);result.success(null);return;}
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
    private void sendBridgeReply(String id,boolean ok,Object value){
        try{
            JSONObject packet=new JSONObject().put("ok",ok).put(ok?"data":"error", !ok&&value instanceof Exception?readableError((Exception)value):value==null?JSONObject.NULL:value);
            if(!ok&&value instanceof QinglongApi.ApiException){QinglongApi.ApiException e=(QinglongApi.ApiException)value;packet.put("errorInfo",new JSONObject().put("httpStatus",e.httpStatus).put("apiCode",e.apiCode).put("permissionDenied",e.permissionDenied));}
            runOnUiThread(()->{MethodChannel.Result result=replies.remove(id);if(result!=null&&!destroyed)result.success(packet.toString());});
        }catch(Exception ignored){}
    }
'''
end='''
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
'''
(java/'MainActivity.java').write_text(prefix+bridge+helpers+end,encoding='utf-8')
assets=app/'android/app/src/main/assets';assets.mkdir(parents=True,exist_ok=True)
shutil.copyfile(root/'app/src/main/assets/editor.js',assets/'editor.js')
for folder in ['drawable-nodpi','mipmap-anydpi-v26']:
    shutil.copytree(root/'app/src/main/res'/folder,app/'android/app/src/main/res'/folder,dirs_exist_ok=True)
for name in ['icon_foreground.xml']:
    shutil.copyfile(root/'app/src/main/res/drawable'/name,app/'android/app/src/main/res/drawable'/name)
shutil.copyfile(root/'app/src/main/res/values/colors.xml',app/'android/app/src/main/res/values/colors.xml')
shutil.copyfile(root/'app/src/main/assets/app-icon.png',app/'assets/app-icon.png')
icon=root/'output/icons/qinglong-landscape-v21-512.png'
if icon.exists():
    for target in [app/'assets/app-icon.png', app/'android/app/src/main/res/drawable-nodpi/app_icon.png']:
        shutil.copyfile(icon,target)
shutil.copyfile(root/'editor/src/notification-fields.json',app/'assets/notifications.json')
for name in ['editor-LICENSE.txt','qinglong-LICENSE.txt','THIRD-PARTY-NOTICES.txt']:
    shutil.copyfile(root/'app/src/main/assets'/name,app/'assets'/name)
print('Synced Android API, encrypted profiles, native glass dock, JD login and editor assets.')
