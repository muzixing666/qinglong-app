package com.qinglong.mobile;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/** Bounded text import. No filesystem access, execution, logging, or remote writes. */
public final class ScriptImportReader {
    public static final int MAX_BYTES = 1024 * 1024;
    private static final Set<String> EXTENSIONS = new HashSet<>(Arrays.asList(
        "js", "mjs", "cjs", "ts", "py", "sh", "bash", "json", "txt",
        "ps1", "php", "rb", "pl", "go", "lua", "yaml", "yml"));

    private ScriptImportReader() {}

    public static void validateFilename(String name) throws IOException {
        validateBasicFilename(name);
        int dot = name.lastIndexOf('.');
        if (dot <= 0 || !EXTENSIONS.contains(name.substring(dot + 1).toLowerCase(Locale.ROOT))) {
            throw new IOException("请选择支持的脚本或文本文件，不支持安装包、可执行文件或压缩包");
        }
    }

    public static void validateConfigFilename(String name) throws IOException {
        validateBasicFilename(name);
        if (name.equals(".env") || name.equals("Dockerfile")) return;
        int dot = name.lastIndexOf('.');
        String ext = dot > 0 ? name.substring(dot + 1).toLowerCase(Locale.ROOT) : "";
        if (!EXTENSIONS.contains(ext) && !Arrays.asList("conf", "ini", "toml", "properties", "xml", "config", "service").contains(ext))
            throw new IOException("请选择支持的 UTF-8 配置文本文件");
    }

    private static void validateBasicFilename(String name) throws IOException {
        if (name == null || name.isEmpty() || name.equals(".") || name.equals("..")
                || name.contains("/") || name.contains("\\")
                || name.getBytes(StandardCharsets.UTF_8).length > 240) {
            throw new IOException("文件名无效、包含路径，或超过 240 个 UTF-8 字节");
        }
        for (int i = 0; i < name.length(); i++) {
            if (Character.isISOControl(name.charAt(i))) throw new IOException("文件名不能包含控制字符");
        }
    }

    /** Caller owns and closes the selected document stream. UTF-8 BOM is preserved. */
    public static Document read(InputStream input, String filename) throws IOException {
        validateFilename(filename);
        return readValidated(input, filename);
    }

    public static Document readConfiguration(InputStream input, String filename) throws IOException {
        validateConfigFilename(filename);
        return readValidated(input, filename);
    }

    private static Document readValidated(InputStream input, String filename) throws IOException {
        if (input == null) throw new IOException("无法打开所选文件，请重新选择");
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        try {
            while (true) {
                if (Thread.currentThread().isInterrupted()) throw new IOException("文件读取已取消");
                int count = input.read(buffer, 0, Math.min(buffer.length, MAX_BYTES - output.size() + 1));
                if (count == -1) break;
                if (count == 0) {
                    int next = input.read();
                    if (next == -1) break;
                    output.write(next);
                } else output.write(buffer, 0, count);
                if (output.size() > MAX_BYTES) throw new TooLarge();
            }
        } catch (TooLarge e) {
            throw new IOException("本地文件超过 1 MiB，请使用网页面板处理");
        } catch (IOException e) {
            // A document provider may put its private content URI in exceptions.
            throw new IOException(Thread.currentThread().isInterrupted()
                ? "文件读取已取消" : "读取所选文件失败，请重新选择已下载到本机的文件");
        }
        byte[] bytes = output.toByteArray();
        String content;
        try {
            content = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException e) {
            throw new IOException("文件不是有效 UTF-8 文本，请转换编码后再上传");
        }
        for (int i = 0; i < content.length(); i++) {
            char c = content.charAt(i);
            if ((c < 32 && c != '\t' && c != '\n' && c != '\r') || c == 127) {
                throw new IOException("文件包含二进制或不支持的控制字符，请选择 UTF-8 文本");
            }
        }
        return new Document(filename, content, bytes.length);
    }

    public static final class Document {
        public final String filename;
        public final String content;
        public final int sizeBytes;
        private Document(String filename, String content, int sizeBytes) {
            this.filename = filename;
            this.content = content;
            this.sizeBytes = sizeBytes;
        }
    }

    private static final class TooLarge extends IOException {}
}
