import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// A self-signed EC P-256 certificate and its private key, both PEM.
class DeviceCertificate {
  const DeviceCertificate({required this.certPem, required this.keyPem});

  final String certPem;
  final String keyPem;

  /// SHA-256 of the DER certificate, lowercase hex. This is what peers pin.
  String get fingerprint => fingerprintOfPem(certPem);

  /// A server context presenting this certificate.
  SecurityContext serverContext() {
    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChainBytes(utf8.encode(certPem));
    ctx.usePrivateKeyBytes(utf8.encode(keyPem));
    return ctx;
  }

  /// Generates a new certificate valid for ten years.
  static DeviceCertificate generate(String commonName) {
    final pair = CryptoUtils.generateEcKeyPair(curve: 'secp256r1');
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem({'CN': commonName}, priv, pub);
    final cert = X509Utils.generateSelfSignedCertificate(
      priv,
      csr,
      3650,
      sans: ['localhost'],
    );
    return DeviceCertificate(
      certPem: cert,
      keyPem: CryptoUtils.encodeEcPrivateKeyToPem(priv),
    );
  }
}

/// SHA-256 fingerprint (lowercase hex) of a PEM certificate's DER bytes.
String fingerprintOfPem(String pem) {
  final der = CryptoUtils.getBytesFromPEMString(pem);
  return fingerprintOfDer(der);
}

/// SHA-256 fingerprint (lowercase hex) of DER certificate bytes.
String fingerprintOfDer(List<int> der) => sha256.convert(der).toString();
