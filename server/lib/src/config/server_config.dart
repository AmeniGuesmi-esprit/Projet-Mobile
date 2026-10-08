import 'dart:io';

import 'package:path/path.dart' as p;

/// Loads configuration from `server/.env` (if present), environment
/// variables taking precedence.
class ServerConfig {
  const ServerConfig({
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPass,
    required this.emailConsoleMode,
    required this.dbPath,
    required this.port,
  });

  final String smtpHost;
  final int smtpPort;
  final String smtpUser;
  final String smtpPass;
  final bool emailConsoleMode;
  final String dbPath;
  final int port;

  static Future<ServerConfig> load({String? envPath}) async {
    final fileEnv = await _readEnvFile(envPath ?? '.env');
    String pick(String key, String fallback) {
      final fromOs = Platform.environment[key];
      if (fromOs != null && fromOs.isNotEmpty) return fromOs;
      final fromFile = fileEnv[key];
      if (fromFile != null && fromFile.isNotEmpty) return fromFile;
      return fallback;
    }

    final rawMode = pick('EMAIL_MODE', 'console').toLowerCase();
    return ServerConfig(
      smtpHost: pick('SMTP_HOST', 'smtp.gmail.com'),
      smtpPort: int.tryParse(pick('SMTP_PORT', '465')) ?? 465,
      smtpUser: pick('SMTP_USER', ''),
      smtpPass: pick('SMTP_PASS', ''),
      emailConsoleMode: rawMode != 'smtp',
      dbPath: p.normalize(pick('DB_PATH', './proxi_life.db')),
      port: int.tryParse(pick('SERVER_PORT', '8080')) ?? 8080,
    );
  }

  static Future<Map<String, String>> _readEnvFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return <String, String>{};
    final map = <String, String>{};
    for (final line in await file.readAsLines()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      final key = trimmed.substring(0, idx).trim();
      var value = trimmed.substring(idx + 1).trim();
      if (value.length >= 2 &&
          value.startsWith('"') &&
          value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      map[key] = value;
    }
    return map;
  }
}
