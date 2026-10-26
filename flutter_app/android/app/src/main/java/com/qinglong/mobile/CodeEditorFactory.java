package com.qinglong.mobile;
import android.content.Context;
import android.graphics.Color;
import android.net.Uri;
import android.view.View;
import android.webkit.*;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.util.HashMap;
import java.util.Map;

/** Offline, isolated code editing component. No API or profile bridge is exposed. */
final class CodeEditorFactory extends PlatformViewFactory {
    private final Context context;
    private Editor current;
    private final Map<Integer,Editor> instances=new HashMap<>();
    private Editor target(Object id){return id instanceof Number?instances.get(((Number)id).intValue()):current;}
    private WebView prepared;
    private boolean preparedLoaded;
    CodeEditorFactory(Context context){super(StandardMessageCodec.INSTANCE);this.context=context;}
    void warm(){
        if(prepared!=null||current!=null)return;
        preparedLoaded=false;
        prepared=makeWeb();
        prepared.loadUrl("https://editor.qinglong.local/editor.html");
    }
    void disposeWarm(){if(prepared!=null){prepared.stopLoading();prepared.destroy();prepared=null;preparedLoaded=false;}}
    @Override public PlatformView create(Context ignored,int id,Object args){current=new Editor(id,(Map<?,?>)args);instances.put(id,current);return current;}
    void isReady(Object id,MethodChannel.Result result){
        Editor editor=target(id);
        if(editor==null){result.success(false);return;}
        editor.web.evaluateJavascript("window.editorReady === true",value->result.success("true".equals(value)));
    }
    void recovery(Object id,MethodChannel.Result result){Editor e=target(id);if(e==null){result.error("EDITOR","编辑器连接已失效",null);return;}result.success(e.latestText);}
    void getText(Object id,MethodChannel.Result result){
        Editor editor=target(id);
        if(editor==null){result.error("EDITOR","编辑器尚未准备好",null);return;}
        editor.web.evaluateJavascript("window.editor && window.editor.view ? window.editor.view.state.doc.toString() : null",value->{
            try {Object decoded=new org.json.JSONTokener(value).nextValue();if(!(decoded instanceof String))throw new Exception();editor.latestText=(String)decoded;result.success(decoded);}
            catch(Exception e){result.error("EDITOR","编辑器尚未准备好，请稍后重试",null);}
        });
    }
    void action(Object input){
        Map<?,?> args=input instanceof Map?(Map<?,?>)input:null;
        Editor e=args==null?current:target(args.get("viewId"));
        String action=args==null?(String)input:(String)args.get("action");
        if(e==null)return;
        WebView web=e.web;
        if(action!=null&&action.matches("jump:[0-9]{1,8}"))web.evaluateJavascript("window.editor && editor.jump("+Integer.parseInt(action.substring(5))+")",null);
        else if(action!=null&&action.matches("font:(?:1[0-9]|2[0-4])"))web.evaluateJavascript("document.documentElement.style.setProperty('--code-font','"+action.substring(5)+"px')",null);
        else if(java.util.Arrays.asList("undo","redo","search","top").contains(action))web.evaluateJavascript("window.editor && editor."+action+"()",null);
    }
    void insert(Object input){
        Map<?,?> args=input instanceof Map?(Map<?,?>)input:null;
        Editor e=args==null?current:target(args.get("viewId"));
        String text=args==null?(String)input:(String)args.get("text");
        if(e==null||text==null||text.length()>1048576)return;
        e.web.evaluateJavascript("window.editor && editor.view.dispatch(editor.view.state.replaceSelection("+JSONObject.quote(text)+"))",null);
    }
    final class Editor implements PlatformView {
        final WebView web;
        final String initial;
        final int id;
        volatile String latestText;
        Editor(int viewId,Map<?,?> args){
            id=viewId;
            boolean loaded=prepared!=null&&preparedLoaded;
            web=prepared!=null?prepared:makeWeb();
            boolean fresh=prepared==null;
            prepared=null;preparedLoaded=false;
            String content=String.valueOf(args.get("content")), filename=String.valueOf(args.get("filename"));
            boolean dark=Boolean.TRUE.equals(args.get("dark"));
            latestText=content.replace("\r\n","\n").replace("\r","\n");
            initial="document.body.dataset.theme="+JSONObject.quote(dark?"dark":"light")+";document.getElementById('source').value="+JSONObject.quote(content)+";window.editor=QLEditor.mount(document.getElementById('source'),"+JSONObject.quote(filename)+");document.getElementById('source').addEventListener('input',function(){clearTimeout(window.syncEditorTimer);window.syncEditorTimer=setTimeout(function(){EditorTextSync.changed(window.editor.view.state.doc.toString());},120);});window.editorReady=true;";
            web.setBackgroundColor(dark?Color.rgb(16,35,52):Color.rgb(248,252,254));
            web.setTag(this);
            if(loaded)web.evaluateJavascript(initial,null);
            else if(fresh)web.loadUrl("https://editor.qinglong.local/editor.html");
        }
        @Override public View getView(){return web;}
        @Override public void dispose(){instances.remove(id);if(current==this)current=instances.values().stream().findFirst().orElse(null);web.setTag(null);web.removeJavascriptInterface("EditorTextSync");web.stopLoading();web.destroy();}
    }
    private WebView makeWeb(){
            WebView web=new WebView(context);
            web.addJavascriptInterface(new Object(){@JavascriptInterface public void changed(String text){Object tag=web.getTag();if(tag instanceof Editor&&text!=null)((Editor)tag).latestText=text;}},"EditorTextSync");
            WebSettings settings=web.getSettings();settings.setJavaScriptEnabled(true);settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);settings.setDomStorageEnabled(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);settings.setSaveFormData(false);
            web.setWebViewClient(new WebViewClient(){
                @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest request){return true;}
                @Override public WebResourceResponse shouldInterceptRequest(WebView v,WebResourceRequest request){
                    Uri uri=request.getUrl();
                    try{
                        String path=uri.getPath();
                        if("https".equals(uri.getScheme())&&"editor.qinglong.local".equals(uri.getHost())&&("/editor.html".equals(path)||"/editor.js".equals(path)))return new WebResourceResponse(path.endsWith("js")?"text/javascript":"text/html","UTF-8",context.getAssets().open(path.substring(1)));
                    }catch(Exception ignored){}
                    return new WebResourceResponse("text/plain","UTF-8",403,"Forbidden",new HashMap<>(),new ByteArrayInputStream(new byte[0]));
                }
                @Override public void onPageFinished(WebView v,String url){
                    if(!url.equals("https://editor.qinglong.local/editor.html"))return;
                    if(v==prepared)preparedLoaded=true;
                    if(v.getTag() instanceof Editor)v.evaluateJavascript(((Editor)v.getTag()).initial,null);
                }
            });
            return web;
    }
}
