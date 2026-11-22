import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../identity/certificate.dart';
import '../pairing/pairing.dart';
import '../protocol/models.dart';

class ClientException implements Exception {
  ClientException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ClientException($statusCode): $message';
}

/// Talks to a paired device over HTTPS. The server's certificate must match
/// [pinnedFingerprint] (SHA-256 of its DER bytes, lowercase hex). Files are
/// streamed, never read whole.
class CoreClient {
  CoreClient({
    required this.host,
    required this.port,
    required this.pinnedFingerprint,
    this.secret,
  });

  final String host;
  final int port;
  final String pinnedFingerprint;

  /// Shared secret from pairing; sent as `Authorization: Bearer <secret>`.
  final String? secret;

  Uri _uri(String path) =>
      Uri(scheme: 'https', host: host, port: port, path: path);

  HttpClient _newHttpClient() {
    final c = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 4);
    c.badCertificateCallback = (cert, h, p) =>
        fingerprintOfDer(cert.der) == pinnedFingerprint;
    return c;
  }

  /// Dev-only trust-on-first-use helper: returns the fingerprint the server
  /// at [host]:[port] presents. Never use this for a paired device.
  static Future<String> probeFingerprint(String host, int port) async {
    String? seen;
    final c = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 4);
    c.badCertificateCallback = (cert, h, p) {
      seen = fingerprintOfDer(cert.der);
      return false;
    };
    try {
      await c.getUrl(Uri(scheme: 'https', host: host, port: port, path: '/'));
    } on Object {
      // Expected: the handshake is rejected after we read the certificate.
    } finally {
      c.close(force: true);
    }
    if (seen == null) throw ClientException('No TLS server at $host:$port');
    return seen!;
  }

  Future<DeviceInfo> getInfo() async {
    final json = await _request('GET', '/api/v1/info');
    return DeviceInfo.fromJson(json);
  }

  /// Pairs with the host using the one-time code. Returns the host's reply;
  /// the caller saves it as a [PairedDevice].
  Future<PairResponse> pair(PairRequest request) async {
    final json = await _request(
      'POST',
      '/api/v1/pair',
      body: utf8.encode(jsonEncode(request.toJson())),
    );
    final response = PairResponse.fromJson(json);
    if (response.fingerprint != pinnedFingerprint) {
      throw ClientException('Paired device presented a different certificate');
    }
    return response;
  }

  Future<void> sendText(TextMessage message) async {
    await _request(
      'POST',
      '/api/v1/text',
      body: utf8.encode(jsonEncode(message.toJson())),
    );
  }

  /// Announces a batch and returns the transfer ID.
  Future<String> sendOffer(TransferOffer offer) async {
    final json = await _request(
      'POST',
      '/api/v1/transfers',
      body: utf8.encode(jsonEncode(offer.toJson())),
    );
    return json['transferId']! as String;
  }

  /// Streams [file] as file [index] of [transferId].
  Future<void> sendFile(
    String transferId,
    int index,
    File file, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = await file.length();
    var sent = 0;
    final stream = file.openRead().map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent, total);
      return chunk;
    });
    await _request(
      'PUT',
      '/api/v1/transfers/$transferId/files/$index',
      stream: stream,
      length: total,
    );
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    List<int>? body,
    Stream<List<int>>? stream,
    int? length,
  }) async {
    final http = _newHttpClient();
    try {
      final req = await http.openUrl(method, _uri(path));
      if (secret != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.contentLength = body.length;
        req.add(body);
      } else if (stream != null) {
        req.headers.contentType = ContentType.binary;
        req.contentLength = length ?? -1;
        await req.addStream(stream);
      }
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      final decoded = text.isEmpty ? <String, Object?>{} : jsonDecode(text);
      if (res.statusCode != 200) {
        final msg = decoded is Map ? '${decoded['error']}' : text;
        throw ClientException(msg, statusCode: res.statusCode);
      }
      return decoded as Map<String, Object?>;
    } on HandshakeException {
      throw ClientException('Certificate does not match the paired device');
    } on SocketException catch (e) {
      throw ClientException('Connection failed: ${e.message}');
    } finally {
      http.close(force: true);
    }
  }
}
