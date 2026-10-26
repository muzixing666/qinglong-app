package com.qinglong.mobile;

import android.app.job.JobService;
import android.app.job.JobParameters;
import org.json.JSONArray;
import org.json.JSONObject;

/** Background widget refresh: read-only requests against the selected panel. */
public final class PanelWidgetJob extends JobService {
    private volatile int generation;
    @Override public boolean onStartJob(JobParameters params){
        final int current=++generation;
        new Thread(()->{
            try {
                ProfileStore store=new ProfileStore(this);JSONObject vault=store.read();String active=vault.optString("activeId");
                JSONObject selected=null;JSONArray servers=vault.optJSONArray("servers");
                if(servers!=null)for(int i=0;i<servers.length();i++)if(active.equals(servers.getJSONObject(i).optString("id"))){selected=servers.getJSONObject(i);break;}
                if(selected==null){PanelWidgetProvider.publish(this,new JSONObject().put("panel","青龙掌控").put("total",-1).put("running",-1).put("status","请先在 App 添加面板"));return;}
                QinglongApi api="password".equals(selected.optString("authMode"))
                    ?QinglongApi.userSession(selected.getString("url"),selected.optString("username"),selected.optString("sessionToken"))
                    :new QinglongApi(selected.getString("url"),selected.optString("clientId"),selected.optString("clientSecret"));
                Object payload=api.request("GET","/crons",null).opt("data");
                JSONArray tasks=payload instanceof JSONArray?(JSONArray)payload:payload instanceof JSONObject?((JSONObject)payload).optJSONArray("data"):null;
                if(tasks==null)throw new java.io.IOException("任务列表格式无效");int running=0;JSONArray names=new JSONArray();
                for(int i=0;i<tasks.length();i++){int status=tasks.getJSONObject(i).optInt("status",1);if(status==0){running++;if(names.length()<3)names.put(tasks.getJSONObject(i).optString("name","未命名任务"));}}
                JSONObject snapshot=new JSONObject().put("serverId",active).put("panel",selected.optString("name","青龙面板")).put("total",tasks.length()).put("running",running).put("runningNames",names).put("updated",System.currentTimeMillis());
                try{JSONObject system=api.request("GET","/system",null).optJSONObject("data");if(system!=null)snapshot.put("version",system.optString("version"));}catch(Exception ignored){}
                try{JSONObject system=api.request("GET","/dashboard/system",null).optJSONObject("data");if(system!=null){snapshot.put("platform",system.optString("platform"));if(system.has("memUsagePercent"))snapshot.put("memory",system.opt("memUsagePercent"));if(system.has("uptime"))snapshot.put("uptime",system.opt("uptime"));}}catch(Exception ignored){}
                if(current==generation&&active.equals(store.read().optString("activeId")))PanelWidgetProvider.publish(this,snapshot);
            } catch(Exception e){
                if(current==generation)PanelWidgetProvider.status(this,e instanceof QinglongApi.ApiException&&((QinglongApi.ApiException)e).httpStatus==401?"请打开 App 重新登录":"刷新失败，点击刷新重试");
            } finally {if(current==generation)jobFinished(params,false);}
        },"qinglong-widget").start();return true;
    }
    @Override public boolean onStopJob(JobParameters params){generation++;PanelWidgetProvider.status(this,"等待网络更新");return true;}
}
