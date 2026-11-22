import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../identity/identity.dart';
import '../pairing/pairing.dart';
import '../protocol/models.dart';
import '../storage/paired_store.dart';
import '../transfer/receiver.dart';

const defaultPort = 47820;

/// Paths that work without the shared secret.
const _openPaths = {'api/v1/info', 'api/v1/pair'};

/// HTTPS server for protocol v1. Everything except `/info` and `/pair`
/// needs the shared secret from pairing (`Authorization: Bearer <secret>`).
class CoreServer {
  CoreServer({
    required this.identity,
    required this.info,
    required this.receiver,
    required this.pairedStore,
    required this.pairing,
    this.onText,
    this.onPaired,
  });

  final DeviceIdentity identity;
  final DeviceInfo info;
  final Receiver receiver;
  final PairedDeviceStore pairedStore;
  final PairingManager pairing;

  /// Called for each text message received.
  final void Function(TextMessage message)? onText;

  /// Called after a device paired with us.
  final void Function(PairedDevice device)? onPaired;

  HttpServer? _server;

  int get port => _server!.port;

  Future<void> start({int port = defaultPort, Object? address}) async {
    final router = Router()
      ..get('/api/v1/info', _info)
      ..post('/api/v1/pair', _pair)
      ..post('/api/v1/transfers', _offer)
      ..put('/api/v1/transfers/<id>/files/<index>', _upload)
      ..post('/api/v1/text', _text);
    final handler = const Pipeline()
        .addMiddleware(_auth)
        .addHandler(router.call);
    _server = await shelf_io.serve(
      handler,
      address ?? InternetAddress.anyIPv4,
      port,
      securityContext: identity.certificate.serverContext(),
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Handler _auth(Handler inner) => (request) async {
    if (_openPaths.contains(request.url.path)) return inner(request);
    final paired = await pairedStore.load();
    final header = request.headers['authorization'] ?? '';
    const prefix = 'Bearer ';
    final given = header.startsWith(prefix)
        ? header.substring(prefix.length)
        : '';
    if (paired == null || !secretsEqual(given, paired.secret)) {
      return _json({'error': 'Unauthorized'}, status: 401);
    }
    return inner(request);
  };

  Response _json(Object body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  Response _info(Request request) => _json(info.toJson());

  Future<Response> _pair(Request request) async {
    final PairRequest req;
    try {
      final body = jsonDecode(await request.readAsString());
      req = PairRequest.fromJson(body as Map<String, Object?>);
    } on Object {
      return _json({'error': 'Bad pairing request'}, status: 400);
    }
    try {
      pairing.consume(req.code);
    } on PairingException catch (e) {
      return _json({'error': e.message}, status: 403);
    }
    final secret = pairing.newSecret();
    final device = PairedDevice(
      id: req.deviceId,
      name: req.deviceName,
      fingerprint: req.fingerprint,
      secret: secret,
    );
    await pairedStore.save(device);
    onPaired?.call(device);
    return _json(
      PairResponse(
        deviceId: identity.id,
        deviceName: identity.name,
        fingerprint: identity.fingerprint,
        secret: secret,
      ).toJson(),
    );
  }

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

  Future<Response> _text(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final message = TextMessage.fromJson(body as Map<String, Object?>);
      onText?.call(message);
      return _json({'ok': true});
    } on Object {
      return _json({'error': 'Bad text message'}, status: 400);
    }
  }
}
