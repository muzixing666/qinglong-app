package com.qinglong.mobile;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewOutlineProvider;
import android.view.animation.PathInterpolator;
import android.widget.FrameLayout;
import android.widget.TextView;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;

/** Independent native optics over an asynchronously sampled Activity strip. */
final class GlassDockView extends FrameLayout {
    interface Listener { void onSelect(String page); }
    private static final String[] PAGES = {"tasks", "envs", "scripts", "more"};
    private static final String[] LABELS = {"任务", "变量", "文件", "我的"};
    private final float density;
    private final int slop;
    private final TextView[] buttons = new TextView[4];
    private final DockIcon[] icons = new DockIcon[4];
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF carrier = new RectF(), lens = new RectF(), lensGlint = new RectF();
    private final Path lensClip = new Path();
    private final Path carrierClip = new Path();
    private static final int MESH_X = 64, MESH_Y = 16;
    private final float[] mesh = new float[(MESH_X + 1) * (MESH_Y + 1) * 2];
    private final float[] carrierMesh = new float[mesh.length], carrierPoints = new float[mesh.length], carrierWarp = new float[mesh.length];
    private Bitmap backdrop, softenedBackdrop;
    private float backdropLeft, backdropTop, backdropWidth, backdropHeight, maxWarp, carrierMaxWarp;
    private long backdropVersion, refractedDraws, carrierRefractedDraws;
    private Shader carrierShader, lensShader, rimShader, lensRimShader;
    private ValueAnimator animator;
    private Listener listener;
    private float cellWidth, lensX, downX, downY, opticalMotion, rimContrast;
    private int selected, pointer = -1;
    private boolean initialized, dark, reduced, dragging, vertical;
    private long lastHaptic, commits, vibrations;
    private long motionGeneration;
    private final boolean debug;
    private final ArrayList<double[]> trace = new ArrayList<>();
    private long traceOrigin;

    GlassDockView(Context context, boolean debug) {
        super(context);
        density = getResources().getDisplayMetrics().density;
        slop = ViewConfiguration.get(context).getScaledTouchSlop();
        this.debug = debug;
        setWillNotDraw(false);
        setClipChildren(false);
        setElevation(dp(7));
        setOutlineProvider(new ViewOutlineProvider() {
            @Override public void getOutline(View view, Outline outline) {
                outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), dp(29));
                outline.setAlpha(.35f);
            }
        });
        setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        for (int i = 0; i < 4; i++) {
            final int index = i;
            TextView button = buttons[i] = new TextView(context);
            icons[i] = new DockIcon(i);
            icons[i].setBounds(0, 0, (int)dp(21), (int)dp(21));
            button.setCompoundDrawables(null, icons[i], null, null);
            button.setCompoundDrawablePadding((int)dp(2));
            button.setText(LABELS[i]);
            button.setTextSize(10);
            button.setTypeface(android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL));
            button.setGravity(Gravity.CENTER);
            button.setPadding(0, (int)dp(4), 0, 0);
            button.setSingleLine(true);
            button.setContentDescription(LABELS[i]);
            button.setFocusable(true);
            button.setClickable(true);
            button.setOnClickListener(view -> commit(index));
            addView(button);
        }
        updateColors();
        setVisibility(View.GONE);
    }

    private float dp(float value) { return value * density; }
    void setListener(Listener listener) { this.listener = listener; }
    private float xFor(int index) { return dp(5) + index * (cellWidth + dp(4)); }
    private int indexAt(float x) { return Math.max(0, Math.min(3, Math.round((x - dp(5) - cellWidth / 2) / (cellWidth + dp(4))))); }
    static int indexFor(String page) {
        if ("tasks".equals(page)) return 0;
        if ("envs".equals(page)) return 1;
        if ("scripts".equals(page) || "configs".equals(page) || "logs".equals(page)) return 2;
        return 3;
    }

    void applyState(String page, boolean visible, boolean dark, boolean reduced, boolean acceptPage) {
        this.reduced = reduced;
        if (this.dark != dark) { this.dark = dark; rebuildShaders(); updateColors(); }
        if (acceptPage) select(indexFor(page), initialized && visible, initialized && visible && getVisibility() == View.VISIBLE);
        initialized = true;
        if (!visible) { cancelGesture(); setVisibility(View.GONE); }
        else setVisibility(View.VISIBLE);
    }

    private void tick() {
        long now = SystemClock.uptimeMillis();
        android.app.Activity owner = (android.app.Activity)getContext();
        if (now - lastHaptic < 90 || !isShown() || !owner.hasWindowFocus()) return;
        lastHaptic = now;
        owner.getWindow().getDecorView().performHapticFeedback(Build.VERSION.SDK_INT >= 34
            ? HapticFeedbackConstants.SEGMENT_FREQUENT_TICK : HapticFeedbackConstants.CLOCK_TICK);
        vibrations++;
    }
    private void commit(int index) {
        boolean changed = selected != index;
        select(index, true, changed);
        if (changed) { commits++; if (listener != null) listener.onSelect(PAGES[index]); }
    }
    private void select(int index, boolean animate, boolean feedback) {
        boolean changed = selected != index;
        selected = index;
        if (changed) { updateColors(); if (feedback) tick(); }
        if (dragging) return;
        float target = xFor(index);
        moveTo(target, animate);
    }
    private float animationTarget = Float.NaN;
    private void moveTo(float target, boolean animate) {
        if (animator != null && animator.isRunning() && target == animationTarget) return;
        if (animator != null) animator.cancel();
        animationTarget = target;
        if (!animate || reduced || !ValueAnimator.areAnimatorsEnabled() || Math.abs(target - lensX) < dp(.2f)) {
            lensX = target; opticalMotion = 0; invalidate(); return;
        }
        animator = ValueAnimator.ofFloat(lensX, target);
        motionGeneration++;
        animator.setDuration(240);
        animator.setInterpolator(new PathInterpolator(.2f, .8f, .2f, 1f));
        animator.addUpdateListener(value -> {
            lensX = (float)value.getAnimatedValue();
            opticalMotion = Math.max(-1f, Math.min(1f, (target - lensX) / cellWidth));
            invalidate();
        });
        animator.start();
    }

    @Override protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        super.onSizeChanged(width, height, oldWidth, oldHeight);
        cellWidth = (width - dp(22)) / 4f;
        if (animator != null) animator.cancel();
        lensX = xFor(selected);
        carrier.set(dp(.7f), dp(.7f), width - dp(.7f), height - dp(.7f));
        rebuildCarrierMesh();
        lens.set(0, 0, cellWidth, dp(48));
        rebuildShaders();
    }
    private void rebuildShaders() {
        if (getWidth() == 0) return;
        carrierShader = new LinearGradient(0, 0, getWidth() * .7f, getHeight(),
            dark ? new int[]{0x50545c70, 0x20262934, 0x50505a70} : new int[]{0x60ffffff, 0x18c8d4e9, 0x48f3f7ff},
            new float[]{0, .5f, 1}, Shader.TileMode.CLAMP);
        lensShader = new LinearGradient(0, 0, cellWidth * .6f, dp(48),
            dark ? new int[]{0x70708db2, 0x20456d9b, 0x6083a1c5} : new int[]{0x90ffffff, 0x389ec7f2, 0x70edf6ff},
            new float[]{0, .55f, 1}, Shader.TileMode.CLAMP);
        // Subtle spectral light follows the capsule rim, never a pair of
        // straight highlight bars crossing the icon row.
        lensRimShader = new android.graphics.SweepGradient(cellWidth / 2f, dp(24),
            dark ? new int[]{0x738bd8e8, 0x20ffffff, 0x99ffd4bc, 0x2888cfe8, 0x738bd8e8}
                 : new int[]{0x6676c9d5, 0x18ffffff, 0x9bffd2af, 0x388ddbe6, 0x6676c9d5},
            new float[]{0, .23f, .50f, .76f, 1});
        rimShader = new android.graphics.SweepGradient(getWidth()/2f,getHeight()/2f,
            dark ? new int[]{0x1097add4,0x68bdcde8,0x1097add4,0x807c9cce,0x1097add4}
                 : new int[]{0x20ffffff,0xc8ffffff,0x28acbad4,0xe8ffffff,0x20ffffff},
            new float[]{0,.24f,.49f,.74f,1});
        invalidate();
    }
    private void updateColors() {
        for (int i = 0; i < 4; i++) {
            int color = i == selected ? (dark ? 0xff74b4ff : 0xff007aff) : (dark ? 0xffbfc1cb : 0xff626673);
            buttons[i].setTextColor(color); buttons[i].setSelected(i == selected); icons[i].color = color; icons[i].active = i == selected; icons[i].invalidateSelf();
        }
    }

    @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        for (int i = 0; i < 4; i++) buttons[i].layout(Math.round(xFor(i)), (int)dp(5), Math.round(xFor(i) + cellWidth), (int)dp(53));
    }
    @Override protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        int width = Math.max(0, Math.round((MeasureSpec.getSize(widthMeasureSpec) - dp(22)) / 4));
        for (TextView button : buttons) button.measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec((int)dp(48), MeasureSpec.EXACTLY));
    }
    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        long started = debug ? System.nanoTime() : 0;
        // Both optical layers sample the actual page. The carrier has softer, wider
        // curvature; the moving lens retains sharper and stronger magnification.
        drawCarrierRefraction(canvas);
        paint.setStyle(Paint.Style.FILL); paint.setShader(null); paint.setColor(dark ? 0x65262934 : 0x3ceef2fa);
        canvas.drawRoundRect(carrier, dp(29), dp(29), paint);
        paint.setAlpha(255); paint.setShader(carrierShader);
        canvas.drawRoundRect(carrier, dp(29), dp(29), paint);
        paint.setShader(null); paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(dp(.9f));
        paint.setColor(Color.WHITE); paint.setShader(rimShader); canvas.drawRoundRect(carrier, dp(29), dp(29), paint);
        paint.setShader(null);
        drawRefraction(canvas);
        canvas.save(); canvas.translate(lensX, dp(5));
        float expansion = dp(1.8f) * Math.abs(opticalMotion);
        lens.set(-expansion * (opticalMotion < 0 ? 1f : .3f), 0,
            cellWidth + expansion * (opticalMotion > 0 ? 1f : .3f), dp(48));
        paint.setStyle(Paint.Style.FILL); paint.setShader(lensShader);
        canvas.drawRoundRect(lens, dp(24), dp(24), paint);
        // Background luminance changes the edge contrast. A single continuous
        // sweep is easier to read than fixed top/bottom stripes on every icon.
        paint.setShader(lensRimShader); paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(dp(1.05f)); paint.setAlpha((int)(116 + 72 * rimContrast));
        canvas.drawRoundRect(lens, dp(24), dp(24), paint);
        paint.setAlpha(255); paint.setShader(null);
        paint.setColor(dark ? 0x67e4f6ff : 0x74ffffff);
        paint.setStrokeWidth(dp(.75f));
        lensGlint.set(lens.left + dp(1.1f), lens.top + dp(1.1f),
            lens.right - dp(1.1f), lens.bottom - dp(1.1f));
        canvas.drawArc(lensGlint, 196 + opticalMotion * 12, 65, false, paint);
        paint.setStyle(Paint.Style.FILL);
        canvas.restore();
        if (debug && (dragging || animator != null && animator.isRunning()) && trace.size() < 512) {
            trace.add(new double[]{SystemClock.uptimeMillis() - traceOrigin, lensX / density, (System.nanoTime() - started) / 1e6, motionGeneration});
        }
    }

    void clearBackdrop() {
        backdrop = null; softenedBackdrop = null; maxWarp = 0; carrierMaxWarp = 0; rimContrast = 0;
        invalidate();
    }
    void setBackdrop(Bitmap bitmap, Bitmap softened, float left, float top, float width, float height) {
        boolean geometryChanged = backdrop == null || backdropLeft != left || backdropTop != top || backdropWidth != width || backdropHeight != height;
        backdrop = bitmap; backdropLeft = left; backdropTop = top; backdropWidth = width; backdropHeight = height;
        // A tiny second texture softens carrier text without a full-screen blur.
        softenedBackdrop = softened;
        rimContrast = lightContrast(lensX + cellWidth / 2f);
        if (geometryChanged) rebuildCarrierMesh();
        backdropVersion++; invalidate();
    }
    private float lightContrast(float x) {
        if (backdrop == null || backdrop.isRecycled() || backdropWidth <= 0 || backdropHeight <= 0) return 0;
        int bx = Math.max(0, Math.min(backdrop.getWidth() - 1,
            Math.round((x - backdropLeft) * backdrop.getWidth() / backdropWidth)));
        int by = Math.max(0, Math.min(backdrop.getHeight() - 1,
            Math.round((dp(29) - backdropTop) * backdrop.getHeight() / backdropHeight)));
        int color = backdrop.getPixel(bx, by);
        float light = (((color >> 16) & 255) * .2126f + ((color >> 8) & 255) * .7152f + (color & 255) * .0722f) / 255f;
        return 1f - light;
    }
    private void rebuildCarrierMesh() {
        if (backdropWidth <= 0 || carrier.isEmpty()) return;
        float radius = carrier.height() / 2, cy = carrier.centerY(), mid = carrier.centerX();
        float coreLeft = carrier.left + radius, coreRight = carrier.right - radius;
        int offset = 0;
        for (int row = 0; row <= MESH_Y; row++) {
            float y = backdropTop + backdropHeight * row / MESH_Y;
            for (int col = 0; col <= MESH_X; col++) {
                float x = backdropLeft + backdropWidth * col / MESH_X;
                float dx = x - Math.max(coreLeft, Math.min(coreRight, x)), dy = y - cy;
                float length = (float)Math.sqrt(dx * dx + dy * dy), depth = radius - length;
                float shiftX = 0, shiftY = 0;
                if (depth > 0) {
                    float bend = (float)Math.sin(Math.min(1f, depth / dp(17)) * Math.PI) * dp(3.5f);
                    if (length > .01f) { shiftX = dx / length * bend; shiftY = dy / length * bend; }
                    float face = Math.min(1f, depth / dp(17));
                    shiftX += (x - mid) * .015f * face; shiftY += (y - cy) * .015f * face;
                }
                carrierPoints[offset] = x; carrierWarp[offset++] = shiftX;
                carrierPoints[offset] = y; carrierWarp[offset++] = shiftY;
            }
        }
        carrierClip.reset(); carrierClip.addRoundRect(carrier, radius, radius, Path.Direction.CW);
    }
    private void drawCarrierRefraction(Canvas canvas) {
        if (softenedBackdrop == null || softenedBackdrop.isRecycled()) return;
        float focus = lensX + cellWidth / 2;
        carrierMaxWarp = 0;
        // Cached geometry keeps the carrier inexpensive. The passing lens changes
        // its optical strength locally, while the outer frame stays completely still.
        for (int i = 0; i < carrierMesh.length; i += 2) {
            float strength = .9f + .3f * Math.max(0, 1 - Math.abs(carrierPoints[i] - focus) / dp(90));
            float dx = carrierWarp[i] * strength, dy = carrierWarp[i + 1] * strength;
            float wake = Math.max(0, 1 - Math.abs(carrierPoints[i] - focus) / dp(70));
            dx += opticalMotion * dp(1.5f) * wake * wake;
            carrierMesh[i] = carrierPoints[i] + dx; carrierMesh[i + 1] = carrierPoints[i + 1] + dy;
            carrierMaxWarp = Math.max(carrierMaxWarp, dx * dx + dy * dy);
        }
        carrierMaxWarp = (float)Math.sqrt(carrierMaxWarp) / density;
        canvas.save(); canvas.clipPath(carrierClip);
        paint.setShader(null); paint.setStyle(Paint.Style.FILL); paint.setColor(Color.WHITE); paint.setFilterBitmap(true);
        canvas.drawBitmapMesh(softenedBackdrop, MESH_X, MESH_Y, carrierMesh, 0, null, 0, paint);
        // A small clear component preserves the half-soft optical depth. It uses
        // the same live mesh, without a second capture or a moving outer shell.
        if(backdrop!=null&&!backdrop.isRecycled()) {
            paint.setAlpha(36);canvas.drawBitmapMesh(backdrop,MESH_X,MESH_Y,carrierMesh,0,null,0,paint);paint.setAlpha(255);
        }
        canvas.restore(); carrierRefractedDraws++;
    }
    private void drawRefraction(Canvas canvas) {
        if (backdrop == null || backdrop.isRecycled()) return;
        float radius = dp(24), cy = dp(29), mid = lensX + cellWidth / 2;
        float expansion = dp(1.8f) * Math.abs(opticalMotion);
        float left = lensX - expansion * (opticalMotion < 0 ? 1f : .3f);
        float right = lensX + cellWidth + expansion * (opticalMotion > 0 ? 1f : .3f);
        float coreLeft = left + radius, coreRight = right - radius;
        int offset = 0; maxWarp = 0;
        for (int row = 0; row <= MESH_Y; row++) {
            float y = backdropTop + backdropHeight * row / MESH_Y;
            for (int col = 0; col <= MESH_X; col++) {
                float x = backdropLeft + backdropWidth * col / MESH_X;
                float nearestX = Math.max(coreLeft, Math.min(coreRight, x)), dx = x - nearestX, dy = y - cy;
                float length = (float)Math.sqrt(dx * dx + dy * dy), depth = radius - length;
                float shiftX = 0, shiftY = 0;
                if (depth > 0) {
                    // A curved boundary bends the real sampled image; the center magnifies it gently.
                    float edge = Math.min(1f, depth / dp(13));
                    float bend = (float)Math.sin(edge * Math.PI) * dp(6.2f);
                    if (length > .01f) { shiftX = dx / length * bend; shiftY = dy / length * bend; }
                    // Keep the center optically quiet, as in an edge-masked
                    // displacement map. Text behind it remains legible.
                }
                mesh[offset++] = x + shiftX; mesh[offset++] = y + shiftY;
                maxWarp = Math.max(maxWarp, (float)Math.sqrt(shiftX * shiftX + shiftY * shiftY) / density);
            }
        }
        canvas.save(); lensClip.reset();
        lensClip.addRoundRect(left, dp(5), right, dp(53), radius, radius, Path.Direction.CW);
        canvas.clipPath(lensClip);
        paint.setShader(null); paint.setStyle(Paint.Style.FILL); paint.setColor(Color.WHITE); paint.setFilterBitmap(true);
        canvas.drawBitmapMesh(softenedBackdrop, MESH_X, MESH_Y, mesh, 0, null, 0, paint);
        paint.setAlpha(76);canvas.drawBitmapMesh(backdrop,MESH_X,MESH_Y,mesh,0,null,0,paint);paint.setAlpha(255);
        canvas.restore(); refractedDraws++;
        rimContrast = lightContrast(mid);
    }

    @Override public boolean onInterceptTouchEvent(MotionEvent event) { return true; }
    @Override public boolean onTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_DOWN) {
            pointer = event.getPointerId(0); downX = event.getX(); downY = event.getY(); dragging = false; vertical = false;
            getParent().requestDisallowInterceptTouchEvent(true); return true;
        }
        if (pointer == -1) return false;
        if (action == MotionEvent.ACTION_CANCEL || action == MotionEvent.ACTION_POINTER_DOWN) { cancelGesture(); return true; }
        int index = event.findPointerIndex(pointer); if (index < 0) { cancelGesture(); return true; }
        float x = event.getX(index), y = event.getY(index), dx = x - downX, dy = y - downY;
        if (Math.abs(dy) > slop && Math.abs(dy) > Math.abs(dx)) vertical = true;
        if (action == MotionEvent.ACTION_MOVE && !vertical && Math.abs(dx) > slop) {
            if (!dragging) motionGeneration++;
            dragging = true; if (animator != null) animator.cancel();
            float next = Math.max(dp(5), Math.min(xFor(3), x - cellWidth / 2));
            opticalMotion = Math.max(-1f, Math.min(1f, (next - lensX) / dp(14)));
            lensX = next; invalidate(); return true;
        }
        if (action == MotionEvent.ACTION_UP) {
            pointer = -1; dragging = false; getParent().requestDisallowInterceptTouchEvent(false);
            if (vertical || y < -dp(20) || y > getHeight() + dp(20)) moveTo(xFor(selected), true);
            else { performClick(); commit(indexAt(x)); }
            return true;
        }
        return true;
    }
    @Override public boolean performClick() { super.performClick(); return true; }
    private void cancelGesture() { pointer = -1; dragging = false; vertical = false; moveTo(xFor(selected), false); }
    void dispose() { if (animator != null) animator.cancel(); listener = null; backdrop = null; softenedBackdrop = null; }
    void resetTrace() { trace.clear(); traceOrigin = SystemClock.uptimeMillis(); }
    JSONObject diagnostics() throws Exception {
        int[] location = new int[2]; getLocationOnScreen(location);
        JSONArray samples = new JSONArray(); for (double[] sample : trace) samples.put(new JSONArray(sample));
        return new JSONObject().put("native", true).put("hardwareAccelerated", isHardwareAccelerated())
            .put("selected", PAGES[selected]).put("visible", getVisibility() == View.VISIBLE)
            .put("left", location[0]).put("top", location[1]).put("width", getWidth()).put("height", getHeight())
            .put("density", density).put("lensX", lensX / density).put("commits", commits).put("haptics", vibrations).put("trace", samples)
            .put("dark", dark).put("reducedMotion", reduced).put("iconVariants", new JSONArray(new boolean[]{selected == 0, selected == 1, selected == 2, selected == 3}))
            .put("backdropVersion", backdropVersion).put("textureWidth", backdrop == null ? 0 : backdrop.getWidth())
            .put("textureHeight", backdrop == null ? 0 : backdrop.getHeight()).put("refractionMaxDp", maxWarp).put("refractedDraws", refractedDraws)
            .put("carrierRefractionMaxDp", carrierMaxWarp).put("carrierRefractedDraws", carrierRefractedDraws)
            .put("opticalMotion", opticalMotion).put("adaptiveRimContrast", rimContrast);
    }
    String debugBackdrop() {
        if (backdrop == null) return "";
        java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream();
        backdrop.compress(Bitmap.CompressFormat.PNG, 100, output);
        return android.util.Base64.encodeToString(output.toByteArray(), android.util.Base64.NO_WRAP);
    }

    private final class DockIcon extends Drawable {
        final int kind; int color; boolean active;
        final Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
        final Path path = new Path();
        DockIcon(int kind) { this.kind = kind; pen.setStyle(Paint.Style.STROKE); pen.setStrokeWidth(1.7f); pen.setStrokeCap(Paint.Cap.ROUND); pen.setStrokeJoin(Paint.Join.ROUND); }
        @Override public void draw(Canvas canvas) {
            canvas.save(); canvas.translate(getBounds().left, getBounds().top); canvas.scale(getBounds().width() / 24f, getBounds().height() / 24f); pen.setColor(color);
            pen.setStrokeWidth(active ? 1.95f : 1.65f);
            if (active) {
                pen.setStyle(Paint.Style.FILL); pen.setColor((color & 0x00ffffff) | 0x25000000);
                if (kind == 0) canvas.drawRoundRect(4, 4, 20, 22, 3, 3, pen);
                else if (kind == 1) { canvas.drawCircle(9, 12, 2, pen); canvas.drawCircle(15, 12, 2, pen); }
                else if (kind == 2) { path.reset(); path.moveTo(3, 6); path.lineTo(3, 21); path.lineTo(21, 21); path.lineTo(21, 8); path.lineTo(12, 8); path.lineTo(10, 4); path.lineTo(3, 4); path.close(); canvas.drawPath(path, pen); }
                else { canvas.drawCircle(12, 7, 4, pen); canvas.drawRoundRect(5, 15, 19, 22, 5, 5, pen); }
                pen.setStyle(Paint.Style.STROKE); pen.setColor(color);
            }
            if (kind == 0) { canvas.drawRoundRect(4, 4, 20, 22, 3, 3, pen); canvas.drawLine(9, 2, 9, 6, pen); canvas.drawLine(15, 2, 15, 6, pen); canvas.drawLine(8, 11, 16, 11, pen); canvas.drawLine(8, 16, 13, 16, pen); }
            else if (kind == 1) { path.reset(); path.moveTo(8, 3); path.lineTo(5, 3); path.lineTo(5, 9); path.lineTo(2, 12); path.lineTo(5, 15); path.lineTo(5, 21); path.lineTo(8, 21); path.moveTo(16, 3); path.lineTo(19, 3); path.lineTo(19, 9); path.lineTo(22, 12); path.lineTo(19, 15); path.lineTo(19, 21); path.lineTo(16, 21); canvas.drawPath(path, pen); canvas.drawCircle(9, 12, .6f, pen); canvas.drawCircle(15, 12, .6f, pen); }
            else if (kind == 2) { path.reset(); path.moveTo(3, 6); path.lineTo(3, 21); path.lineTo(21, 21); path.lineTo(21, 8); path.lineTo(12, 8); path.lineTo(10, 4); path.lineTo(3, 4); path.close(); canvas.drawPath(path, pen); }
            else { canvas.drawCircle(12, 7, 4, pen); path.reset(); path.moveTo(4, 22); path.lineTo(4, 20); path.cubicTo(4, 10, 20, 10, 20, 20); path.lineTo(20, 22); canvas.drawPath(path, pen); }
            canvas.restore();
        }
        @Override public void setAlpha(int alpha) { pen.setAlpha(alpha); }
        @Override public void setColorFilter(android.graphics.ColorFilter filter) { pen.setColorFilter(filter); }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }
}
