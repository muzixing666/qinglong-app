package com.qinglong.mobile;

import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;

/** Fetch an explicitly supplied source URL without any panel cookies or token. */
final class RemoteScriptReader {
    static ScriptImportReader.Document read(String url, String filename, boolean allowHttp) throws IOException {
        return read(url, filename, allowHttp, false);
    }
    static ScriptImportReader.Document read(String url, String filename, boolean allowHttp, boolean configuration) throws IOException {
        if (configuration) ScriptImportReader.validateConfigFilename(filename); else ScriptImportReader.validateFilename(filename);
        URI uri;
        try { uri = new URI(url); } catch (Exception e) { throw new IOException("远程地址格式无效"); }
        if (uri.getHost() == null || uri.getRawUserInfo() != null || uri.getRawFragment() != null ||
            !("https".equals(uri.getScheme()) || "http".equals(uri.getScheme())))
            throw new IOException("请填写不含账号或片段的 HTTP(S) 文件直链");
        if ("http".equals(uri.getScheme()) && !allowHttp) throw new IOException("远程 HTTP 下载需要明确允许明文连接");
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) uri.toURL().openConnection();
            connection.setConnectTimeout(15000); connection.setReadTimeout(30000);
            connection.setInstanceFollowRedirects(false); connection.setUseCaches(false);
            connection.setRequestProperty("Accept", "text/plain, application/octet-stream, */*");
            connection.setRequestProperty("User-Agent", "QinglongControl/0.17.0");
            int status = connection.getResponseCode();
            if (status >= 300 && status < 400) throw new IOException("远程链接发生跳转，请填写最终文件直链");
            if (status != 200) throw new IOException("远程服务器返回 HTTP " + status);
            String type = connection.getContentType();
            if (type != null && type.toLowerCase(java.util.Locale.ROOT).contains("text/html"))
                throw new IOException("链接返回了网页，请使用 Raw 文件直链");
            if (connection.getContentLengthLong() > ScriptImportReader.MAX_BYTES) throw new IOException("远程文件超过 1 MiB");
            try (InputStream input = connection.getInputStream()) { return configuration ? ScriptImportReader.readConfiguration(input, filename) : ScriptImportReader.read(input, filename); }
        } catch (javax.net.ssl.SSLException e) { throw new IOException("远程 HTTPS 证书或 TLS 验证失败"); }
        catch (java.net.SocketTimeoutException e) { throw new IOException("远程文件下载超时"); }
        catch (IOException e) {
            String message = e.getMessage();
            if (message != null && (message.startsWith("远程") || message.startsWith("链接") || message.contains("UTF-8") || message.contains("二进制") || message.contains("控制字符"))) throw new IOException(message);
            throw new IOException("无法获取远程脚本，请检查文件直链和网络");
        } finally { if (connection != null) connection.disconnect(); }
    }
}
