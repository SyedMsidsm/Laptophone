import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../identity/identity.dart';
import '../protocol/models.dart';
import '../transfer/receiver.dart';

const defaultPort = 47820;

/// HTTPS server for protocol v1 (auth is added in Task 6).
class CoreServer {
  CoreServer({
    required this.identity,
    required this.info,
    required this.receiver,
  });

  final DeviceIdentity identity;
  final DeviceInfo info;
  final Receiver receiver;
  HttpServer? _server;

  int get port => _server!.port;

  Future<void> start({int port = defaultPort, Object? address}) async {
    final router = Router()
      ..get('/api/v1/info', _info)
      ..post('/api/v1/transfers', _offer)
      ..put('/api/v1/transfers/<id>/files/<index>', _upload);
    _server = await shelf_io.serve(
      router.call,
      address ?? InternetAddress.anyIPv4,
      port,
      securityContext: identity.certificate.serverContext(),
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Response _json(Object body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  Response _info(Request request) => _json(info.toJson());

  Future<Response> _offer(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final offer = TransferOffer.fromJson(body as Map<String, Object?>);
      return _json({'transferId': receiver.handleOffer(offer)});
    } on ReceiveException catch (e) {
      return _json({'error': e.message}, status: e.statusCode);
    } on Object {
      return _json({'error': 'Bad offer'}, status: 400);
    }
  }

  Future<Response> _upload(Request request, String id, String index) async {
    final i = int.tryParse(index);
    if (i == null) return _json({'error': 'Bad index'}, status: 400);
    try {
      await receiver.receiveFile(id, i, request.read());
      return _json({'ok': true});
    } on ReceiveException catch (e) {
      return _json({'error': e.message}, status: e.statusCode);
    }
  }
}
