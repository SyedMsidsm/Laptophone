import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol/models.dart';

class ClientException implements Exception {
  ClientException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ClientException($statusCode): $message';
}

/// Talks to a paired device. Files are streamed, never read whole.
class CoreClient {
  CoreClient({required this.host, required this.port});

  final String host;
  final int port;

  Uri _uri(String path) =>
      Uri(scheme: 'http', host: host, port: port, path: path);

  Future<DeviceInfo> getInfo() async {
    final json = await _request('GET', '/api/v1/info');
    return DeviceInfo.fromJson(json);
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
    final http = HttpClient();
    try {
      final req = await http.openUrl(method, _uri(path));
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
    } on SocketException catch (e) {
      throw ClientException('Connection failed: ${e.message}');
    } finally {
      http.close(force: true);
    }
  }
}
