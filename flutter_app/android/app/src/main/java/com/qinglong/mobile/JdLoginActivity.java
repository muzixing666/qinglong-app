package com.qinglong.mobile;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebStorage;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import java.io.ByteArrayInputStream;
import java.util.HashMap;
import java.util.HashSet;

/** Dedicated official-site browser. It has NO native JavaScript bridge. */
public final class JdLoginActivity extends Activity {
    private static final String LOGIN = "https://plogin.m.jd.com/login/login";
    private static final String HOME = "https://m.jd.com/";
    private static final String FIXTURE_HTML = "<!doctype html><meta name='viewport' content='width=device-width'><p>仅用于本地回归测试，不发送京东请求。</p><button id='fixture-login' onclick=\"document.cookie='pt_key=synthetic-jd-test; path=/; Secure';document.cookie='pt_pin=fixture_account; path=/; Secure';this.textContent='本地测试已登录'\">模拟登录</button>";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final HashSet<String> origins = new HashSet<>();
    private WebView browser;
    private TextView status;
    private Button extract;
    private ProgressBar progress;
    private boolean fixture, active, closing, lastReady;
    private final Runnable poll = new Runnable() {
        @Override public void run() {
            if (!active || closing) return;
            updateCookieState(); handler.postDelayed(this, 900);
        }
    };

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        getWindow().setStatusBarColor(Color.rgb(237,240,244));
        getWindow().setNavigationBarColor(Color.rgb(237,240,244));
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        fixture = (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0 && getIntent().getBooleanExtra("fixture", false);
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(0xffedf0f4);
        LinearLayout header = new LinearLayout(this); header.setGravity(android.view.Gravity.CENTER_VERTICAL); header.setPadding(dp(8),dp(4),dp(8),dp(4));
        Button back = button("返回"); back.setOnClickListener(v -> complete(null)); header.addView(back);
        TextView title = new TextView(this); title.setText(fixture ? "京东登录 · 本地测试" : "京东网页登录"); title.setTextSize(16); title.setTextColor(0xff232b3a); title.setGravity(android.view.Gravity.CENTER);
        header.addView(title, new LinearLayout.LayoutParams(0,dp(48),1));
        Button reload = button("重载"); reload.setOnClickListener(v -> browser.reload()); header.addView(reload); root.addView(header);
        progress = new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal); progress.setMax(100); root.addView(progress,new LinearLayout.LayoutParams(-1,dp(2)));
        browser = new WebView(this); WebSettings settings = browser.getSettings();
        settings.setJavaScriptEnabled(true); settings.setDomStorageEnabled(true); settings.setSaveFormData(false);
        settings.setAllowFileAccess(false); settings.setAllowContentAccess(false); settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setJavaScriptCanOpenWindowsAutomatically(false); settings.setSupportMultipleWindows(false);
        if (Build.VERSION.SDK_INT >= 26) settings.setSafeBrowsingEnabled(true);
        CookieManager.getInstance().setAcceptCookie(true); CookieManager.getInstance().setAcceptThirdPartyCookies(browser,false);
        browser.setWebChromeClient(new WebChromeClient(){@Override public void onProgressChanged(WebView v,int value){progress.setProgress(value);progress.setVisibility(value==100?View.INVISIBLE:View.VISIBLE);}});
        browser.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest request){
                boolean allowed=JdSessionRules.allowedPage(request.getUrl().toString());
                if(!allowed)status.setText("只在此窗口打开京东 HTTPS 网页；请使用网页登录方式。");
                return !allowed;
            }
            @Override public void onPageStarted(WebView v,String url,android.graphics.Bitmap icon){
                if(JdSessionRules.allowedPage(url)){android.net.Uri uri=android.net.Uri.parse(url);origins.add("https://"+uri.getHost());}
            }
            @Override public void onPageFinished(WebView v,String url){updateCookieState();}
            @Override public void onReceivedError(WebView v,WebResourceRequest r,android.webkit.WebResourceError e){if(r.isForMainFrame())status.setText("页面加载失败，可重载，或返回使用粘贴 CK。");}
            @Override public WebResourceResponse shouldInterceptRequest(WebView v,WebResourceRequest request){
                if(fixture && HOME.equals(request.getUrl().toString()))return new WebResourceResponse("text/html","UTF-8",new ByteArrayInputStream(FIXTURE_HTML.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
                if(fixture || !"https".equalsIgnoreCase(request.getUrl().getScheme()))return new WebResourceResponse("text/plain","UTF-8",403,"Forbidden",new HashMap<>(),new ByteArrayInputStream(new byte[0]));
                return null;
            }
        });
        root.addView(browser,new LinearLayout.LayoutParams(-1,0,1));
        status = new TextView(this); status.setText("请在京东官方页面手动登录，完成后点击提取。无需在青龙表单填写京东密码。"); status.setTextSize(12); status.setTextColor(0xff526078); status.setPadding(dp(16),dp(9),dp(16),dp(5)); root.addView(status);
        LinearLayout actions = new LinearLayout(this); actions.setPadding(dp(10),0,dp(10),dp(8));
        Button change = button("切换账号"); change.setOnClickListener(v -> clearSession(() -> {if(!closing)loadLogin();})); actions.addView(change,new LinearLayout.LayoutParams(0,dp(48),1));
        extract = button("提取 CK"); extract.setEnabled(false); extract.setTextColor(0xff344f96); extract.setOnClickListener(v -> {String cookie=readCookie();if(cookie==null){status.setText("尚未检测到完整的网页 CK，请完成登录后重试。");return;}complete(cookie);}); actions.addView(extract,new LinearLayout.LayoutParams(0,dp(48),1)); root.addView(actions);
        setContentView(root);
        if(Build.VERSION.SDK_INT>=33)getOnBackInvokedDispatcher().registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,()->complete(null));
        clearSession(this::loadLogin);
    }
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private Button button(String text){Button b=new Button(this);b.setText(text);b.setTextSize(13);b.setAllCaps(false);b.setMinWidth(dp(62));b.setPadding(dp(8),0,dp(8),0);return b;}
    private void loadLogin(){
        if(closing)return;
        lastReady=false;extract.setEnabled(false);status.setText("请在京东官方页面手动登录，完成后点击提取。");
        browser.loadUrl(fixture?HOME:LOGIN);
    }
    private String readCookie(){
        if(browser==null||!JdSessionRules.allowedPage(browser.getUrl()))return null;
        CookieManager cookies=CookieManager.getInstance();
        for(String url:new String[]{browser.getUrl(),HOME,"https://plogin.m.jd.com/","https://home.m.jd.com/"}){
            String value=JdSessionRules.webCookie(cookies.getCookie(url));if(value!=null)return value;
        }
        return null;
    }
    private void updateCookieState(){
        if(browser==null||extract==null||closing)return;
        boolean ready=readCookie()!=null;if(extract.isEnabled()!=ready)extract.setEnabled(ready);
        if(ready&&!lastReady)status.setText("已检测到网页 CK。点击提取，返回后核对账号并确认导入；不推测 MCK / APPCK 来源。");
        else if(!ready&&lastReady)status.setText("登录状态已变化，请完成登录后再提取。");
        lastReady=ready;
    }
    private void clearSession(Runnable done){
        // Main UI is an offline origin and panel sessions use ProfileStore, not
        // WebView cookies. Only this app's cookie jar is cleared, never JD App's.
        CookieManager.getInstance().removeAllCookies(ignored -> {
            CookieManager.getInstance().flush();
            for(String origin:origins)WebStorage.getInstance().deleteOrigin(origin);
            origins.clear(); if(!isDestroyed())done.run();
        });
    }
    private void complete(String cookie){
        if(closing)return;closing=true;active=false;handler.removeCallbacks(poll);browser.stopLoading();
        final Intent result=cookie==null?null:new Intent().putExtra("cookie",cookie);
        clearSession(()->{setResult(result==null?RESULT_CANCELED:RESULT_OK,result);finish();});
    }
    @Override public void onBackPressed(){complete(null);}
    @Override protected void onResume(){super.onResume();active=true;handler.removeCallbacks(poll);handler.post(poll);}
    @Override protected void onPause(){active=false;handler.removeCallbacks(poll);super.onPause();}
    @Override protected void onDestroy(){if(!closing)clearSession(()->{});handler.removeCallbacksAndMessages(null);if(browser!=null){browser.stopLoading();browser.destroy();browser=null;}super.onDestroy();}
}
