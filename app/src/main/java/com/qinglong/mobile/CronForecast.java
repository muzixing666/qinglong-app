package com.qinglong.mobile;

import com.cronutils.model.CronType;
import com.cronutils.model.definition.CronDefinitionBuilder;
import com.cronutils.model.time.ExecutionTime;
import com.cronutils.parser.CronParser;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.HashMap;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;

/** Local estimates only. The server remains the authority for actual dispatch. */
public final class CronForecast {
    private static final CronParser PARSER = new CronParser(
        CronDefinitionBuilder.instanceDefinitionFor(CronType.SPRING53));
    private CronForecast() {}

    public static Long next(String expression, String zone, long afterMillis) {
        String value=expression == null ? "" : expression.trim();
        if(value.length()>256 || value.isEmpty() || value.equals("@reboot")) return null;
        if(value.split("\\s+").length==5) value="0 "+value;
        try {
            com.cronutils.model.Cron parsed=PARSER.parse(value);parsed.validate();
            ZonedDateTime after=ZonedDateTime.ofInstant(Instant.ofEpochMilli(afterMillis),ZoneId.of(zone));
            String[] fields=value.split("\\s+");
            // Qinglong's cron-parser uses UNIX OR when both day fields are
            // restricted. SPRING53 evaluates them together, so take the union.
            if(fields.length==6 && !fields[3].equals("*") && !fields[3].equals("?")
                    && !fields[5].equals("*") && !fields[5].equals("?")) {
                String day=fields[3];fields[3]="*";
                Long weekday=nextParsed(String.join(" ",fields),after);
                fields[3]=day;fields[5]="*";
                Long monthday=nextParsed(String.join(" ",fields),after);
                return weekday==null?monthday:monthday==null?weekday:Math.min(weekday,monthday);
            }
            return ExecutionTime.forCron(parsed).nextExecution(after).map(time -> time.toInstant().toEpochMilli()).orElse(null);
        } catch (IllegalArgumentException | java.time.DateTimeException error) { return null; }
    }

    private static Long nextParsed(String rule,ZonedDateTime after) {
        return ExecutionTime.forCron(PARSER.parse(rule)).nextExecution(after)
            .map(time -> time.toInstant().toEpochMilli()).orElse(null);
    }

    public static JSONObject batch(JSONObject input) throws Exception {
        String requested=input.optString("timezone", "").trim();
        String zone=requested.isEmpty()?ZoneId.systemDefault().getId():requested;
        JSONArray tasks=input.optJSONArray("tasks"), result=new JSONArray();
        long now=input.optLong("now",System.currentTimeMillis());
        boolean validZone;
        try {ZoneId.of(zone);validZone=true;}catch(Exception error){validZone=false;}
        Map<String,Long> memo=new HashMap<>();
        if(tasks!=null) for(int i=0;i<Math.min(tasks.length(),10000);i++) {
            JSONObject task=tasks.optJSONObject(i);if(task==null)continue;
            JSONObject row=new JSONObject().put("id",task.opt("id"));
            Long earliest=null;
            if(validZone) {
                JSONArray rules=new JSONArray().put(task.optString("schedule"));
                JSONArray extra=task.optJSONArray("extra_schedules");
                if(extra!=null)for(int j=0;j<extra.length();j++) {
                    JSONObject additional=extra.optJSONObject(j);
                    if(additional!=null)rules.put(additional.optString("schedule"));
                }
                for(int j=0;j<rules.length();j++) {
                    String expression=rules.optString(j);
                    if(!memo.containsKey(expression))memo.put(expression,next(expression,zone,now));
                    Long value=memo.get(expression);
                    if(value!=null&&(earliest==null||value<earliest))earliest=value;
                }
            }
            row.put("next",earliest==null?JSONObject.NULL:earliest);
            row.put("state",!validZone?"unknown-zone":earliest==null?"unsupported":"estimated");
            result.put(row);
        }
        return new JSONObject().put("rows",result).put("zone",zone)
            .put("source",requested.isEmpty()?"device":"panel").put("calculatedAt",now);
    }
}
