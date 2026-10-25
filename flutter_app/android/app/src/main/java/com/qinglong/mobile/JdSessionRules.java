package com.qinglong.mobile;

import java.net.URI;

/** Validation shared by the login window and local JVM tests; never logs values. */
final class JdSessionRules {
    static boolean allowedPage(String value) {
        try {
            URI uri = new URI(value);
            String host = uri.getHost();
            return "https".equalsIgnoreCase(uri.getScheme()) && host != null
                && (host.equalsIgnoreCase("jd.com") || host.toLowerCase(java.util.Locale.ROOT).endsWith(".jd.com"))
                && uri.getRawUserInfo() == null && (uri.getPort() == -1 || uri.getPort() == 443);
        } catch (Exception ignored) { return false; }
    }

    static String webCookie(String header) {
        if (header == null || header.length() > 32768 || header.indexOf('\r') >= 0 || header.indexOf('\n') >= 0) return null;
        String key = null, pin = null;
        for (String part : header.split(";")) {
            int equals = part.indexOf('=');
            if (equals < 0) continue;
            String name = part.substring(0, equals).trim(), value = part.substring(equals + 1).trim();
            if (!name.equals("pt_key") && !name.equals("pt_pin")) continue;
            if (value.isEmpty() || value.length() > 16384 || value.matches(".*[\\s\\p{Cntrl}].*")) return null;
            if (name.equals("pt_key")) { if (key != null && !key.equals(value)) return null; key = value; }
            else { if (pin != null && !pin.equals(value)) return null; pin = value; }
        }
        return key == null || pin == null ? null : "pt_key=" + key + "; pt_pin=" + pin + ";";
    }
}
