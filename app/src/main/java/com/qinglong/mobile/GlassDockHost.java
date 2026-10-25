package com.qinglong.mobile;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.drawable.ColorDrawable;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.PixelCopy;
import android.view.View;
import android.view.WindowManager;
import android.widget.PopupWindow;

/** Separate application-panel surface lets PixelCopy sample only the Activity below it. */
final class GlassDockHost {
    final GlassDockView dock;
    private final Activity activity;
    private final View root;
    private final PopupWindow window;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final HandlerThread copyThread = new HandlerThread("GlassBackgroundCopy");
    private final Handler copyHandler;
    private final float density;
    private boolean wanted, paused, disposed, copying, scheduled, dirty, urgentDirty;
    private long lastCopy;
    private int epoch;
    private boolean frameSynchronized, awaitingFrame, appearanceDark;
    private String contentPage = "", backdropPage = "";
    private long discardedCopies;
    void synchronizeWithFrames() { frameSynchronized = true; }
    String backdropPage() { return backdropPage; }
    boolean awaitingFrame() { return awaitingFrame; }
    long discardedCopies() { return discardedCopies; }
    void pageFrameReady(String page) {
        if (!frameSynchronized || !page.equals(contentPage) || disposed || paused || !wanted) return;
        final int readyEpoch = epoch;
        // Dart's post-frame callback precedes raster presentation. Let the new
        // TextureView frame reach the Activity surface before PixelCopy samples it.
        root.postOnAnimation(() -> root.postOnAnimation(() -> {
            if (readyEpoch != epoch || disposed || paused || !wanted) return;
            awaitingFrame = false;
            // On some emulators the Flutter TextureView is presented after
            // the Dart frame callback and two Android vsyncs. Capturing at
            // that instant can freeze the previous page into the dock until
            // the next scroll. Keep the carrier clear, then sample twice with
            // an epoch guard; this runs only on navigation, not each frame.
            main.postDelayed(() -> {
                if (readyEpoch == epoch && !disposed && !paused && wanted) requestSample();
            }, 64);
            main.postDelayed(() -> {
                if (readyEpoch == epoch && !disposed && !paused && wanted) requestSample();
            }, 220);
        }));
    }
    private int lastX, lastY, lastWidth, lastHeight;
    private final Runnable sample = () -> { scheduled = false; copyBackground(); };

    GlassDockHost(Activity activity, View root, boolean debug) {
        this.activity = activity; this.root = root;
        density = root.getResources().getDisplayMetrics().density;
        dock = new GlassDockView(activity, debug);
        window = new PopupWindow(dock, 1, Math.round(58 * density), false);
        window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        window.setElevation(7 * density);
        window.setClippingEnabled(false);
        if (android.os.Build.VERSION.SDK_INT >= 29) window.setIsLaidOutInScreen(true);
        window.setInputMethodMode(PopupWindow.INPUT_METHOD_NOT_NEEDED);
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING);
        copyThread.start(); copyHandler = new Handler(copyThread.getLooper());
        root.addOnLayoutChangeListener((view,l,t,r,b,ol,ot,or,ob) -> { if (wanted) show(); });
    }

    void applyState(String page, boolean visible, boolean dark, boolean reduced, boolean acceptPage) {
        if (disposed) return;
        if (frameSynchronized && acceptPage &&
                (!page.equals(contentPage) || dark != appearanceDark || visible && !wanted)) {
            epoch++; awaitingFrame = true; contentPage = page; appearanceDark = dark;
            backdropPage = ""; dock.clearBackdrop();
        }
        wanted = visible;
        dock.applyState(page, visible, dark, reduced, acceptPage);
        if (wanted && !paused) show(); else hide();
        if (visible) requestSample();
    }
    private void show() {
        if (disposed || paused || !wanted || root.getWindowToken() == null || root.getWidth() == 0) return;
        int width = Math.min(Math.round(872 * density), root.getWidth() - root.getPaddingLeft() - root.getPaddingRight() - Math.round(24 * density));
        int height = Math.round(58 * density);
        int[] location = new int[2]; root.getLocationOnScreen(location);
        int x = location[0] + root.getPaddingLeft() + (root.getWidth() - root.getPaddingLeft() - root.getPaddingRight() - width) / 2;
        int y = location[1] + root.getHeight() - root.getPaddingBottom() - height - Math.round(10 * density);
        int gravity = Gravity.TOP | Gravity.LEFT;
        if (android.os.Build.VERSION.SDK_INT < 29) {
            // Before API 29 PopupWindow positions inside the application display frame.
            gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
            x = 0; y = root.getPaddingBottom() + Math.round(10 * density);
        }
        if (!window.isShowing()) {
            window.setWidth(width); window.setHeight(height);
            window.showAtLocation(root, gravity, x, y);
        } else if(x != lastX || y != lastY || width != lastWidth || height != lastHeight) window.update(x, y, width, height);
        lastX=x; lastY=y; lastWidth=width; lastHeight=height;
        requestSample();
        dock.postOnAnimation(this::requestSample);
    }
    private void hide() {
        epoch++; dirty = false; urgentDirty = false; main.removeCallbacks(sample); scheduled = false;
        if (frameSynchronized) { awaitingFrame = true; backdropPage = ""; dock.clearBackdrop(); }
        if (window.isShowing()) window.dismiss();
    }
    void pause() { paused = true; hide(); }
    void resume() { paused = false; root.post(this::show); }
    void requestSample() { requestSample(true); }
    void requestAnimatedSample() { requestSample(false); }
    private void requestSample(boolean urgent) {
        if (disposed || paused || !wanted || !window.isShowing() || awaitingFrame) return;
        dirty = true; urgentDirty |= urgent;
        if (copying) return;
        if (scheduled) {
            if (!urgent) return;
            main.removeCallbacks(sample); scheduled = false;
        }
        scheduleSample();
    }
    private void scheduleSample() {
        if (copying || scheduled || !dirty || disposed || paused || !wanted) return;
        scheduled = true;
        // Scroll/route changes stay responsive. Small looping page indicators do
        // not need a new optical texture every frame or a second 30-Hz render loop.
        main.postDelayed(sample, Math.max(0, (urgentDirty ? 32 : 96) - (SystemClock.uptimeMillis() - lastCopy)));
    }
    private void copyBackground() {
        if (disposed || paused || !wanted || !window.isShowing() || copying || awaitingFrame || dock.getWidth() == 0) return;
        View decor = activity.getWindow().getDecorView();
        int[] position = new int[2], origin = new int[2]; dock.getLocationOnScreen(position); decor.getLocationOnScreen(origin);
        int pad = Math.round(10 * density);
        Rect area = new Rect(position[0] - origin[0] - pad, position[1] - origin[1] - pad,
            position[0] - origin[0] + dock.getWidth() + pad, position[1] - origin[1] + dock.getHeight() + pad);
        if (!area.intersect(0, 0, decor.getWidth(), decor.getHeight()) || area.isEmpty()) return;
        // At most a narrow strip and one pending copy, never a full-screen bitmap.
        Bitmap bitmap = Bitmap.createBitmap(Math.max(1, area.width() / 2), Math.max(1, area.height() / 2), Bitmap.Config.ARGB_8888);
        final int currentEpoch = epoch;
        final float left = area.left + origin[0] - position[0], top = area.top + origin[1] - position[1];
        copying = true; dirty = false; urgentDirty = false; lastCopy = SystemClock.uptimeMillis();
        try {
            PixelCopy.request(activity.getWindow(), area, bitmap, result -> {
                // Downsampling and blur run off the UI/animation thread.
                Bitmap softened = result == PixelCopy.SUCCESS ? soften(bitmap) : null;
                main.post(() -> {
                copying = false;
                if (!disposed && currentEpoch == epoch && wanted && !paused && !awaitingFrame && result == PixelCopy.SUCCESS) {
                    dock.setBackdrop(bitmap, softened, left, top, area.width(), area.height());
                    backdropPage = contentPage;
                } else discardedCopies++;
                // Replaced textures are released by Android/GC after RenderThread drops them.
                if (dirty) scheduleSample();
            });
            }, copyHandler);
        } catch (IllegalArgumentException error) { copying = false; }
    }
    private static Bitmap soften(Bitmap bitmap) {
        Bitmap small = Bitmap.createScaledBitmap(bitmap, Math.max(1, bitmap.getWidth()/2), Math.max(1, bitmap.getHeight()/2), true);
        int w=small.getWidth(), h=small.getHeight(); int[] pixels=new int[w*h], scratch=new int[w*h];
        small.getPixels(pixels,0,w,0,0,w,h);
        for(int pass=0;pass<2;pass++) {
            blurAxis(pixels,scratch,w,h,true); blurAxis(scratch,pixels,w,h,false);
        }
        Bitmap result=Bitmap.createBitmap(pixels,w,h,Bitmap.Config.ARGB_8888);
        if(small!=bitmap)small.recycle();
        return result;
    }
    private static void blurAxis(int[] from,int[] to,int w,int h,boolean horizontal) {
        int size=horizontal?w:h, lines=horizontal?h:w;
        for(int line=0;line<lines;line++) {
            int r=0,g=0,b=0;
            for(int k=-2;k<=2;k++){int pos=Math.max(0,Math.min(size-1,k));int c=from[horizontal?line*w+pos:pos*w+line];r+=(c>>16)&255;g+=(c>>8)&255;b+=c&255;}
            for(int i=0;i<size;i++) {
                to[horizontal?line*w+i:i*w+line]=0xff000000|((r/5)<<16)|((g/5)<<8)|(b/5);
                int a=Math.max(0,i-2),z=Math.min(size-1,i+3);
                int old=from[horizontal?line*w+a:a*w+line],next=from[horizontal?line*w+z:z*w+line];
                r+=((next>>16)&255)-((old>>16)&255);g+=((next>>8)&255)-((old>>8)&255);b+=(next&255)-(old&255);
            }
        }
    }
    void dispose() {
        disposed = true; hide(); dock.dispose(); copyThread.quitSafely();
    }
}
