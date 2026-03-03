library;

class DirectDomainMatcher {
  static List<String> normalizeDomainList(Iterable<String> domains) {
    final normalized = <String>{};
    for (final value in domains) {
      final host = extractHost(value);
      if (host != null && host.isNotEmpty) {
        normalized.add(host);
      }
    }
    return normalized.toList();
  }

  static bool matchesEndpoint(String endpoint, Iterable<String> domainRules) {
    final host = extractHost(endpoint);
    if (host == null) {
      return false;
    }
    return matchesHost(host, domainRules);
  }

  static bool matchesHost(String host, Iterable<String> domainRules) {
    final normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return false;
    }

    for (final rule in domainRules) {
      final normalizedRule = extractHost(rule);
      if (normalizedRule == null || normalizedRule.isEmpty) {
        continue;
      }

      if (normalizedHost == normalizedRule ||
          normalizedHost.endsWith('.$normalizedRule')) {
        return true;
      }
    }

    return false;
  }

  static String? extractHost(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      return null;
    }

    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
        value = value.substring(1, value.length - 1).trim();
      }
    }

    if (value.isEmpty) {
      return null;
    }

    if (value.startsWith('*.')) {
      value = value.substring(2);
    } else if (value.startsWith('.')) {
      value = value.substring(1);
    }

    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(value);
    final uri = Uri.tryParse(hasScheme ? value : 'https://$value');
    if (uri != null && uri.host.isNotEmpty) {
      return _normalizeHost(uri.host);
    }

    var hostPart = value;
    final slashIndex = hostPart.indexOf('/');
    if (slashIndex >= 0) {
      hostPart = hostPart.substring(0, slashIndex);
    }
    final queryIndex = hostPart.indexOf('?');
    if (queryIndex >= 0) {
      hostPart = hostPart.substring(0, queryIndex);
    }
    final hashIndex = hostPart.indexOf('#');
    if (hashIndex >= 0) {
      hostPart = hostPart.substring(0, hashIndex);
    }

    hostPart = hostPart.trim();
    if (hostPart.isEmpty) {
      return null;
    }

    if (hostPart.startsWith('[')) {
      final rightBracket = hostPart.indexOf(']');
      if (rightBracket > 1) {
        return _normalizeHost(hostPart.substring(1, rightBracket));
      }
    }

    final firstColon = hostPart.indexOf(':');
    final lastColon = hostPart.lastIndexOf(':');
    if (firstColon > 0 && firstColon == lastColon) {
      hostPart = hostPart.substring(0, lastColon);
    }

    final normalized = _normalizeHost(hostPart);
    return normalized.isEmpty ? null : normalized;
  }

  static String _normalizeHost(String host) {
    var value = host.trim().toLowerCase();
    if (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
