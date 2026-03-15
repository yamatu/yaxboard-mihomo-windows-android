import 'dart:convert';

String normalizeJson(String raw) {
  var cleaned = raw.trim();
  cleaned = cleaned.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
  cleaned = cleaned.replaceAll(RegExp(r'\s+//.*$', multiLine: true), '');
  cleaned = cleaned.trim();
  final firstBrace = cleaned.indexOf('{');
  if (firstBrace == -1) return cleaned;
  var level = 0;
  var endIndex = -1;
  for (var i = firstBrace; i < cleaned.length; i++) {
    final ch = cleaned[i];
    if (ch == '{') level++;
    else if (ch == '}') { level--; if (level == 0) { endIndex = i; break; } }
  }
  if (endIndex != -1) cleaned = cleaned.substring(firstBrace, endIndex + 1);
  return cleaned.trim();
}

void main() {
  final input = '''
{
    "panelType": "xboard", // 支持 "xboard" 或 "v2board"
    "panels": {
        "mihomo": [ // "mihomo" 可以是任意名称
            {
                "url": "https://yamatu.xyz:7001",
                "description": "主面板"
            }
        ]
    },
    "onlineSupport": [
        {
            "url": "https://yamatu.xyz:7001",
            "description": "在线客服",
            "apiBaseUrl": "https://yamatu.xyz:7001",
            "wsBaseUrl": "wss://yamatu.xyz:7001"
        }
    ]
}''';

  final result = normalizeJson(input);
  print('Result:');
  print(result);
  try {
    final parsed = jsonDecode(result);
    print('\nParsed successfully!');
    print('panelType: ${parsed["panelType"]}');
    final panels = parsed['panels']['mihomo'] as List;
    print('panel url: ${panels[0]["url"]}');
  } catch (e) {
    print('\nJSON parse FAILED: $e');
  }
}
