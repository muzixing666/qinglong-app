package com.qinglong.mobile;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ConnectException;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;
import java.net.URLEncoder;
import java.net.UnknownHostException;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

import javax.net.ssl.SSLException;

/** Synchronous OpenAPI client. Call from a worker thread, never the main thread. */
public final class QinglongApi {
    private static final int CONNECT_TIMEOUT_MS = 15_000;
    private static final int READ_TIMEOUT_MS = 30_000;
    private static final int MAX_RESPONSE_BYTES = 16 * 1024 * 1024;
    private final String baseUrl;
    private final String clientId;
    private final String clientSecret;
    private final boolean userMode;
    private String token;
    private long expirationSeconds;

    public QinglongApi(String baseUrl, String clientId, String clientSecret) {
        this(baseUrl, clientId, clientSecret, false, null);
    }

    private QinglongApi(String baseUrl, String identity, String secret, boolean userMode, String session) {
        this.baseUrl = normalizeBaseUrl(baseUrl);
        this.userMode = userMode;
        this.clientId = identity == null ? "" : identity.trim();
        this.clientSecret = secret == null ? "" : userMode ? secret : secret.trim();
        this.token = session;
        if (!userMode && (this.clientId.isEmpty() || this.clientSecret.isEmpty())) {
            throw new IllegalArgumentException("Client ID 和 Client Secret 不能为空");
        }
    }

    public static QinglongApi userSession(String baseUrl, String username, String session) {
        return new QinglongApi(baseUrl, username, "", true, session);
    }

    /** Login once; OTP challenges are explicit and are never automatically replayed. */
    public static QinglongApi loginUser(String baseUrl, String username, String password, String otp) throws IOException {
        QinglongApi api = new QinglongApi(baseUrl, username, password, true, null);
        if (api.clientId.isEmpty() || password == null || password.isEmpty()) throw new IOException("请填写账号和密码");
        try {
            JSONObject body = new JSONObject().put("username", api.clientId).put("password", password);
            boolean secondFactor = otp != null && !otp.isEmpty();
            if (secondFactor) body.put("code", otp);
            JSONObject result = api.checked(api.exchange(secondFactor ? "PUT" : "POST",
                secondFactor ? "/api/user/two-factor/login" : "/api/user/login", body, null), true);
            JSONObject data = result.optJSONObject("data");
            if (data == null || data.optString("token").isEmpty()) throw new IOException("面板返回的登录信息无效");
            // The returned session instance holds no account password.
            return userSession(baseUrl, username, data.getString("token"));
        } catch (JSONException e) { throw new IOException("面板返回的登录信息无效"); }
    }

    public synchronized String sessionToken() { return token == null ? "" : token; }

    /**
     * path is /crons, /open/crons, etc.; query parameters must already be URL encoded.
     * body must be a JSONObject, JSONArray, or null. No mutation is retried on a
     * timeout or server error. A rejected 401 refreshes authentication once.
     */
    public synchronized JSONObject request(String method, String path, Object body)
            throws IOException {
        String verb = method == null ? "" : method.toUpperCase(Locale.ROOT);
        if (!verb.equals("GET") && !verb.equals("POST") && !verb.equals("PUT")
                && !verb.equals("DELETE") && !verb.equals("PATCH")) {
            throw new IOException("不支持的 HTTP 方法");
        }
        if (body != null && !(body instanceof JSONObject) && !(body instanceof JSONArray)) {
            throw new IOException("请求体必须是 JSON 对象或数组");
        }
        if (verb.equals("GET") && body != null) {
            throw new IOException("GET 请求不能携带请求体");
        }
        String endpoint = normalizeEndpoint(path);
        if (userMode) endpoint = "/api/" + endpoint.substring("/open/".length());
        if (endpoint.equals("/open/auth/token") || endpoint.startsWith("/open/auth/token?")) {
            throw new IOException("认证接口由客户端自动管理");
        }
        ensureToken(false);
        WireResponse response = exchange(verb, endpoint, body, token);
        if (!userMode && (response.httpStatus == 401 || apiCode(response.json) == 401)
                && !isPermissionDenial(response.json)) {
            ensureToken(true);
            response = exchange(verb, endpoint, body, token);
        }
        if (userMode && (response.httpStatus == 401 || apiCode(response.json) == 401) && !isPermissionDenial(response.json)) invalidateToken();
        boolean mirrorStream = verb.equals("PUT") && (endpoint.equals("/api/system/config/node-mirror")
                || endpoint.equals("/api/system/config/linux-mirror")
                || endpoint.equals("/open/system/config/node-mirror")
                || endpoint.equals("/open/system/config/linux-mirror"));
        if (mirrorStream && response.httpStatus >= 200 && response.httpStatus < 300
                && response.json == null && !response.contentType.toLowerCase(Locale.ROOT).contains("html")
                && !response.raw.trim().startsWith("<")) {
            try {return new JSONObject().put("code",200).put("data",new JSONObject()
                .put("streamed",true).put("output",response.raw));}
            catch(JSONException error){throw new IOException("无法读取镜像设置响应");}
        }
        return checked(response, false);
    }

    public JSONObject request(String method, String path) throws IOException {
        return request(method, path, null);
    }

    /** Tests the supplied application credentials without requiring any module scope. */
    public synchronized void authenticate() throws IOException {
        ensureToken(true);
    }

    /** Handles both {data:[...]} and the cron envelope {data:{data:[...],total:n}}. */
    public static JSONArray listData(JSONObject envelope) throws IOException {
        Object data = envelope == null ? null : envelope.opt("data");
        if (data instanceof JSONArray) return (JSONArray) data;
        if (data instanceof JSONObject) {
            JSONArray rows = ((JSONObject) data).optJSONArray("data");
            if (rows != null) return rows;
        }
        throw new IOException("面板返回的列表格式不受支持，请检查面板版本");
    }

    public synchronized void invalidateToken() {
        token = null;
        expirationSeconds = 0;
    }

    private void ensureToken(boolean force) throws IOException {
        if (userMode) {
            if (token == null || token.isEmpty()) throw new IOException("登录已失效，请在面板连接中重新登录");
            return;
        }
        long now = System.currentTimeMillis() / 1000;
        if (!force && token != null && expirationSeconds > now + 60) return;
        // Invalidate first so a failed refresh cannot leave a rejected token cached.
        token = null;
        expirationSeconds = 0;
        String query = "/open/auth/token?client_id=" + encode(clientId)
                + "&client_secret=" + encode(clientSecret);
        JSONObject result = checked(exchange("GET", query, null, null), true);
        JSONObject data = result.optJSONObject("data");
        if (data == null || data.optString("token", "").isEmpty()
                || data.optLong("expiration", 0) <= now) {
            throw new IOException("面板返回的认证信息无效");
        }
        token = data.optString("token");
        expirationSeconds = data.optLong("expiration");
    }

    private WireResponse exchange(String method, String endpoint, Object body, String bearer)
            throws IOException {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(baseUrl + endpoint).openConnection();
            // Default platform certificate and hostname validation stay enabled.
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
            connection.setReadTimeout(READ_TIMEOUT_MS);
            connection.setUseCaches(false);
            connection.setRequestMethod(method);
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("User-Agent", "QinglongControl/0.17.0 (Linux; Android; Mobile)");
            if (bearer != null) connection.setRequestProperty("Authorization", "Bearer " + bearer);
            if (body != null) {
                byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
                connection.setFixedLengthStreamingMode(bytes.length);
                try (OutputStream output = connection.getOutputStream()) {
                    output.write(bytes);
                }
            }
            int status = connection.getResponseCode();
            InputStream stream = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
            String raw = readResponse(stream);
            JSONObject json = null;
            if (!raw.trim().isEmpty()) {
                try {
                    json = new JSONObject(raw);
                } catch (JSONException ignored) {
                    // HTML proxy/login pages are described without exposing their body.
                }
            }
            return new WireResponse(status, json, raw, connection.getContentType());
        } catch (SocketTimeoutException e) {
            throw new IOException("连接或读取超时。操作可能已被面板接收，请刷新状态后再决定是否重试");
        } catch (SSLException e) {
            throw new IOException("HTTPS 证书校验或 TLS 连接失败，请检查证书、域名及设备时间");
        } catch (UnknownHostException e) {
            throw new IOException("无法解析面板域名，请检查地址和网络");
        } catch (ConnectException e) {
            throw new IOException("无法连接面板，请检查地址、端口和网络");
        } catch (IOException e) {
            // Authentication URLs contain the secret; never propagate a URL-bearing cause.
            throw new IOException(safeMessage(e.getMessage(), "网络请求失败，请检查网络和面板地址"));
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private JSONObject checked(WireResponse response, boolean authentication) throws IOException {
        int code = apiCode(response.json);
        if (authentication && userMode) {
            if (code == 420) throw new TwoFactorRequired();
            if (code == 430) throw new ApiException(response.httpStatus, code, "动态验证码不正确或已使用，请输入新的验证码");
            if (code == 410 || code == 429 || response.httpStatus == 429)
                throw new ApiException(response.httpStatus, code, safeMessage(response.json == null ? "" : response.json.optString("message"), "登录尝试过于频繁，请稍后重试"));
            if (code == 450) throw new ApiException(response.httpStatus, code, "面板未初始化，或双因素验证已超时，请返回重新登录");
        }
        if (response.httpStatus >= 300 && response.httpStatus < 400) {
            throw new ApiException(response.httpStatus, code,
                    "面板返回了重定向，请填写最终地址及正确的反向代理子路径");
        }
        if (response.httpStatus == 403 || code == 403 || isPermissionDenial(response.json)) {
            ApiException denied = new ApiException(response.httpStatus, code,
                    userMode ? "面板拒绝访问，请检查账号、IP限制或文件权限" : "面板拒绝访问，请检查应用模块权限或文件访问限制");
            denied.permissionDenied = true;
            throw denied;
        }
        if (response.httpStatus == 401 || code == 401) {
            throw new ApiException(response.httpStatus, code,
                    userMode ? "登录已失效，请在面板连接中重新登录" : "认证已失效，请检查 Client ID / Secret，或重新保存面板连接");
        }
        if (response.httpStatus == 404 || code == 404 || code == 410) {
            throw new ApiException(response.httpStatus, code,
                    "此接口不存在或已下线，请检查面板地址、子路径和版本兼容性");
        }
        if (response.httpStatus == 429 || code == 429) {
            throw new ApiException(response.httpStatus, code, "请求过于频繁，请稍后再试");
        }
        if (response.json == null) {
            throw new ApiException(response.httpStatus, 0,
                    "服务器返回了非 JSON 响应（HTTP " + response.httpStatus
                            + "），请检查地址、反向代理及面板状态");
        }
        if (response.httpStatus < 200 || response.httpStatus >= 300 || code != 200) {
            String message = authentication && code == 400
                    ? userMode ? "账号或密码不正确" : "Client ID 或 Client Secret 不正确"
                    : safeMessage(response.json.optString("message", ""), "面板请求失败");
            throw new ApiException(response.httpStatus, code,
                    message + "（HTTP " + response.httpStatus + ", code " + code + "）");
        }
        return response.json;
    }

    private String safeMessage(String message, String fallback) {
        if (message == null || message.trim().isEmpty()) return fallback;
        String safe = message;
        for (String value : new String[]{clientSecret, clientId, token}) {
            if (value != null && !value.isEmpty()) safe = safe.replace(value, "[已隐藏]").replace(encode(value), "[已隐藏]");
        }
        if (token != null && !token.isEmpty()) safe = safe.replace(token, "[已隐藏]");
        safe = safe.replaceAll("[\\r\\n\\t]+", " ");
        return safe.length() > 220 ? safe.substring(0, 220) + "…" : safe;
    }

    private static int apiCode(JSONObject json) {
        return json == null ? 0 : json.optInt("code", 0);
    }

    private static boolean isPermissionDenial(JSONObject json) {
        if (json == null) return false;
        String message = json.optString("message", "").toLowerCase(Locale.ROOT);
        return message.contains("暂无权限") || message.contains("没有权限")
                || message.contains("no permission") || message.contains("permission denied")
                || message.contains("forbidden");
    }

    private static String readResponse(InputStream stream) throws IOException {
        if (stream == null) return "";
        try (InputStream input = stream; ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) {
                if (output.size() + count > MAX_RESPONSE_BYTES) {
                    throw new IOException("响应超过 16 MB，请缩小查询范围或分段读取日志");
                }
                output.write(buffer, 0, count);
            }
            return new String(output.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    private static String normalizeBaseUrl(String value) {
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException("面板地址不能为空");
        }
        try {
            URI uri = new URI(value.trim());
            String scheme = uri.getScheme();
            if (!("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme))
                    || uri.getHost() == null || uri.getRawUserInfo() != null
                    || uri.getRawQuery() != null || uri.getRawFragment() != null) {
                throw new IllegalArgumentException("请输入完整的 HTTP(S) 面板根地址，可包含反向代理子路径");
            }
            String path = uri.getPath();
            if (path != null && (path.contains("\\") || hasDotSegment(path))) {
                throw new IllegalArgumentException("面板地址的路径无效");
            }
            String result = uri.toASCIIString();
            while (result.endsWith("/")) result = result.substring(0, result.length() - 1);
            return result;
        } catch (URISyntaxException e) {
            throw new IllegalArgumentException("面板地址格式不正确");
        }
    }

    private static String normalizeEndpoint(String value) throws IOException {
        if (value == null || value.isEmpty()) throw new IOException("接口路径不能为空");
        String relative = value.startsWith("/") ? value : "/" + value;
        try {
            URI uri = new URI(relative);
            String path = uri.getPath();
            if (uri.isAbsolute() || uri.getRawAuthority() != null || uri.getRawFragment() != null
                    || path == null || path.contains("\\") || hasDotSegment(path)
                    || path.contains("//") || path.startsWith("/api/") || path.equals("/api")) {
                throw new IOException("仅允许相对的 OpenAPI 接口路径");
            }
            String endpoint = relative.startsWith("/open/") ? relative : "/open" + relative;
            if (!endpoint.startsWith("/open/")) throw new IOException("OpenAPI 接口路径无效");
            return endpoint;
        } catch (URISyntaxException e) {
            throw new IOException("接口路径或查询参数格式不正确");
        }
    }

    private static boolean hasDotSegment(String path) {
        for (String segment : path.split("/")) {
            if (segment.equals(".") || segment.equals("..")) return true;
        }
        return false;
    }

    public static String encode(String value) {
        try {
            return URLEncoder.encode(value == null ? "" : value, "UTF-8");
        } catch (java.io.UnsupportedEncodingException impossible) {
            throw new AssertionError(impossible);
        }
    }

    private static final class WireResponse {
        final int httpStatus;
        final JSONObject json;
        final String raw, contentType;
        WireResponse(int httpStatus, JSONObject json, String raw, String contentType) {
            this.httpStatus = httpStatus;
            this.json = json;
            this.raw = raw == null ? "" : raw;
            this.contentType = contentType == null ? "" : contentType;
        }
    }

    public static final class ApiException extends IOException {
        public boolean permissionDenied;
        public final int httpStatus;
        public final int apiCode;
        ApiException(int httpStatus, int apiCode, String message) {
            super(message);
            this.httpStatus = httpStatus;
            this.apiCode = apiCode;
        }
    }

    public static final class TwoFactorRequired extends IOException {
        TwoFactorRequired() { super("此账号已开启双因素验证，请输入动态验证码"); }
    }
}
