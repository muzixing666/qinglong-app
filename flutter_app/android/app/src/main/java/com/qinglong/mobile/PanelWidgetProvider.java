package com.qinglong.mobile;

import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.*;
import android.os.Bundle;
import android.widget.RemoteViews;
import org.json.JSONObject;

/** Read-only widget snapshots: system summary, task counts and running names. */
public final class PanelWidgetProvider extends AppWidgetProvider {
    static final String REFRESH="com.qinglong.mobile.WIDGET_REFRESH";
    static final int JOB=22001;
    static JSONObject snapshot(Context c){
        try{return new JSONObject(c.getSharedPreferences("panel_widget",0).getString("snapshot","{}"));}
        catch(Exception e){return new JSONObject();}
    }
    static void publish(Context c,JSONObject data){
        c.getSharedPreferences("panel_widget",0).edit().putString("snapshot",data.toString()).apply();
        renderAll(c);
    }
    static void status(Context c,String message){
        try{JSONObject data=snapshot(c);data.put("status",message);publish(c,data);}catch(Exception ignored){}
    }
    static void refresh(Context c){
        if(AppWidgetManager.getInstance(c).getAppWidgetIds(new ComponentName(c,PanelWidgetProvider.class)).length==0)return;
        status(c,"正在刷新…");
        JobInfo job=new JobInfo.Builder(JOB,new ComponentName(c,PanelWidgetJob.class))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setOverrideDeadline(1000).build();
        if(c.getSystemService(JobScheduler.class).schedule(job)==JobScheduler.RESULT_FAILURE)status(c,"打开 App 同步面板");
    }
    static PendingIntent open(Context c,String page){
        Intent intent=new Intent(c,MainActivity.class).setAction(Intent.ACTION_VIEW)
            .putExtra("shortcut_page",page)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(c,page.hashCode(),intent,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
    }
    @Override public void onUpdate(Context c,AppWidgetManager manager,int[] ids){renderAll(c);refresh(c);}
    @Override public void onAppWidgetOptionsChanged(Context c,AppWidgetManager m,int id,Bundle options){renderAll(c);}
    @Override public void onDisabled(Context c){c.getSystemService(JobScheduler.class).cancel(JOB);}
    @Override public void onReceive(Context c,Intent intent){super.onReceive(c,intent);if(REFRESH.equals(intent.getAction()))refresh(c);}
    static void renderAll(Context c){
        AppWidgetManager manager=AppWidgetManager.getInstance(c);
        JSONObject data=snapshot(c);
        boolean dark=c.getSharedPreferences("flutter_appearance",0).getBoolean("dark",false);
        int ink=dark?0xffedf4ff:0xff20394c,muted=dark?0xffaebed1:0xff60768b,accent=dark?0xff82c5ff:0xff007aff;
        for(int id:manager.getAppWidgetIds(new ComponentName(c,PanelWidgetProvider.class))){
            RemoteViews v=new RemoteViews(c.getPackageName(),R.layout.panel_widget);
            Bundle options=manager.getAppWidgetOptions(id);
            int width=Math.max(220,options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,280));
            int height=Math.max(140,options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,150));
            v.setImageViewBitmap(R.id.widget_background,glass(480,Math.max(180,Math.min(480,480*height/width)),dark));
            v.setTextViewText(R.id.widget_name,data.optString("panel","青龙掌控"));
            v.setTextViewText(R.id.widget_total,data.optInt("total",-1)<0?"—":String.valueOf(data.optInt("total")));
            v.setTextViewText(R.id.widget_running,data.optInt("running",-1)<0?"—":String.valueOf(data.optInt("running")));
            String status=data.optString("status","");long updated=data.optLong("updated",0);
            if(status.isEmpty())status=updated>0?"更新于 "+new java.text.SimpleDateFormat("MM/dd HH:mm",java.util.Locale.CHINA).format(new java.util.Date(updated)):"打开 App 同步面板";
            v.setTextViewText(R.id.widget_status,status);
            String version=data.optString("version","");String system=version.isEmpty()?"系统信息暂不可用":"青龙 "+version;
            if(!data.optString("platform").isEmpty())system+=" · "+data.optString("platform");
            if(data.has("memory"))system+=" · 内存 "+data.optString("memory")+"%";
            if(data.has("uptime"))system+=" · 运行 "+(data.optLong("uptime")/3600)+"h";
            v.setTextViewText(R.id.widget_system,system);
            org.json.JSONArray names=data.optJSONArray("runningNames");StringBuilder activity=new StringBuilder();
            if(names!=null)for(int i=0;i<names.length();i++){if(i>0)activity.append("\n");activity.append("• ").append(names.optString(i));}
            if(data.optInt("running",-1)>3)activity.append("\n另有 ").append(data.optInt("running")-3).append(" 个任务运行中");
            v.setTextViewText(R.id.widget_activity,activity.length()>0?activity.toString():data.optInt("running",-1)==0?"当前暂无运行任务":"打开 App 同步运行任务");
            v.setTextColor(R.id.widget_system,muted);v.setTextColor(R.id.widget_activity,ink);
            v.setViewVisibility(R.id.widget_activity,height>=210?android.view.View.VISIBLE:android.view.View.GONE);
            v.setOnClickPendingIntent(R.id.widget_activity,open(c,"tasks"));
            v.setTextColor(R.id.widget_name,ink);v.setTextColor(R.id.widget_total,accent);v.setTextColor(R.id.widget_running,accent);
            for(int text:new int[]{R.id.widget_total_label,R.id.widget_running_label,R.id.widget_status})v.setTextColor(text,muted);
            for(int text:new int[]{R.id.widget_refresh,R.id.widget_tasks,R.id.widget_envs,R.id.widget_scripts})v.setTextColor(text,accent);
            v.setOnClickPendingIntent(R.id.widget_name,open(c,"more"));
            v.setOnClickPendingIntent(R.id.widget_tasks,open(c,"tasks"));v.setOnClickPendingIntent(R.id.widget_envs,open(c,"envs"));v.setOnClickPendingIntent(R.id.widget_scripts,open(c,"scripts"));
            v.setOnClickPendingIntent(R.id.widget_total,open(c,"tasks"));v.setOnClickPendingIntent(R.id.widget_running,open(c,"tasks"));
            v.setOnClickPendingIntent(R.id.widget_refresh,PendingIntent.getBroadcast(c,JOB,new Intent(c,PanelWidgetProvider.class).setAction(REFRESH),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE));
            manager.updateAppWidget(id,v);
        }
    }
    static Bitmap glass(int width,int height,boolean dark){
        Bitmap image=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(image);
        Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);RectF bounds=new RectF(2,2,width-2,height-2);float radius=width*.075f;
        p.setShader(new LinearGradient(0,0,width,height,dark?new int[]{0xd528354b,0xb51a273c,0xd3213047}:new int[]{0xdff9fdff,0xb7e6f1ff,0xc9e6ebfa},null,Shader.TileMode.CLAMP));
        canvas.drawRoundRect(bounds,radius,radius,p);
        Path clip=new Path();clip.addRoundRect(bounds,radius,radius,Path.Direction.CW);canvas.save();canvas.clipPath(clip);
        p.setShader(new RadialGradient(width*.86f,height*.05f,width*.7f,new int[]{0x72ffffff,0x00ffffff},null,Shader.TileMode.CLAMP));canvas.drawRect(bounds,p);
        Path reflection=new Path();reflection.moveTo(0,0);reflection.lineTo(width,0);reflection.cubicTo(width*.7f,height*.4f,width*.25f,-height*.05f,0,height*.28f);reflection.close();
        p.setShader(new LinearGradient(0,0,0,height*.4f,new int[]{0x60ffffff,0x00ffffff},null,Shader.TileMode.CLAMP));canvas.drawPath(reflection,p);canvas.restore();
        p.setStyle(Paint.Style.STROKE);p.setStrokeWidth(1.5f);p.setShader(new LinearGradient(0,0,width,height,new int[]{0xdfffffff,0x28ffffff,0x6fa6c9f5},null,Shader.TileMode.CLAMP));canvas.drawRoundRect(bounds,radius,radius,p);
        return image;
    }
}
