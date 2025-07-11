// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_BIN_SECURITY_CONTEXT_H_
#define RUNTIME_BIN_SECURITY_CONTEXT_H_

#include <openssl/ssl.h>
#include <openssl/x509.h>

#include "bin/lockers.h"
#include "bin/reference_counting.h"
#include "bin/socket.h"

namespace dart {
namespace bin {

// Forward declaration
class SSLFilter;

typedef void (*TrustEvaluateHandlerFunc)(Dart_Port dest_port_id,
                                         Dart_CObject* message);

class SSLCertContext : public ReferenceCounted<SSLCertContext> {
 public:
  static const intptr_t kApproximateSize;
  static constexpr int kSecurityContextNativeFieldIndex = 0;
  static constexpr int kX509NativeFieldIndex = 0;

  explicit SSLCertContext(SSL_CTX* context)
      : ReferenceCounted(),
        context_(context),
        alpn_protocol_string_(nullptr),
        trust_builtin_(false),
        allow_tls_renegotiation_(false) {}

  ~SSLCertContext() {
    SSL_CTX_free(context_);
    free(alpn_protocol_string_);
  }

  static int CertificateCallback(int preverify_ok, X509_STORE_CTX* store_ctx);
  static void KeyLogCallback(const SSL* ssl, const char* line);

  static SSLCertContext* GetSecurityContext(Dart_NativeArguments args);
  static const char* GetPasswordArgument(Dart_NativeArguments args,
                                         intptr_t index);
  static void SetAlpnProtocolList(Dart_Handle protocols_handle,
                                  SSL* ssl,
                                  SSLCertContext* context,
                                  bool is_server);

  static const char* root_certs_file() { return root_certs_file_; }
  static void set_root_certs_file(const char* root_certs_file) {
    root_certs_file_ = root_certs_file;
  }
  static const char* root_certs_cache() { return root_certs_cache_; }
  static void set_root_certs_cache(const char* root_certs_cache) {
    root_certs_cache_ = root_certs_cache;
  }

  void SetTrustedCertificatesBytes(Dart_Handle cert_bytes,
                                   const char* password);

  void SetClientAuthoritiesBytes(Dart_Handle client_authorities_bytes,
                                 const char* password);

  int UseCertificateChainBytes(Dart_Handle cert_chain_bytes,
                               const char* password);

  void TrustBuiltinRoots();

  SSL_CTX* context() const { return context_; }

  uint8_t* alpn_protocol_string() const { return alpn_protocol_string_; }

  void set_alpn_protocol_string(uint8_t* protocol_string) {
    if (alpn_protocol_string_ != nullptr) {
      free(alpn_protocol_string_);
    }
    alpn_protocol_string_ = protocol_string;
  }

  bool trust_builtin() const { return trust_builtin_; }

  void set_allow_tls_renegotiation(bool allow) {
    allow_tls_renegotiation_ = allow;
  }
  bool allow_tls_renegotiation() const { return allow_tls_renegotiation_; }

  void set_trust_builtin(bool trust_builtin) { trust_builtin_ = trust_builtin; }

  void RegisterCallbacks(SSL* ssl);
  static TrustEvaluateHandlerFunc GetTrustEvaluateHandler();

  static bool long_ssl_cert_evaluation() { return long_ssl_cert_evaluation_; }
  static void set_long_ssl_cert_evaluation(bool long_ssl_cert_evaluation) {
    long_ssl_cert_evaluation_ = long_ssl_cert_evaluation;
  }

  static bool bypass_trusting_system_roots() {
    return bypass_trusting_system_roots_;
  }
  static void set_bypass_trusting_system_roots(
      bool bypass_trusting_system_roots) {
    bypass_trusting_system_roots_ = bypass_trusting_system_roots;
  }

 private:
  void AddCompiledInCerts();
  void LoadRootCertFile(const char* file);
  void LoadRootCertCache(const char* cache);

  static const char* root_certs_file_;
  static const char* root_certs_cache_;

  SSL_CTX* context_;
  uint8_t* alpn_protocol_string_;

  bool trust_builtin_;
  bool allow_tls_renegotiation_;
  static bool long_ssl_cert_evaluation_;
  static bool bypass_trusting_system_roots_;

  DISALLOW_COPY_AND_ASSIGN(SSLCertContext);
};

class X509Helper : public AllStatic {
 public:
  static Dart_Handle GetDer(Dart_NativeArguments args);
  static Dart_Handle GetPem(Dart_NativeArguments args);
  static Dart_Handle GetSha1(Dart_NativeArguments args);
  static Dart_Handle GetSubject(Dart_NativeArguments args);
  static Dart_Handle GetIssuer(Dart_NativeArguments args);
  static Dart_Handle GetStartValidity(Dart_NativeArguments args);
  static Dart_Handle GetEndValidity(Dart_NativeArguments args);
  static Dart_Handle WrappedX509Certificate(X509* certificate);
};

}  // namespace bin
}  // namespace dart

#endif  // RUNTIME_BIN_SECURITY_CONTEXT_H_
