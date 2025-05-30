// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analysis_server/src/socket_server.dart';
import 'package:analysis_server/src/status/diagnostics.dart';

/// Instances of the class [AbstractHttpHandler] handle HTTP requests.
abstract class AbstractHttpHandler {
  /// Handle a GET request received by the HTTP server.
  void handleGetRequest(HttpRequest request);

  /// Handle a POST request received by the HTTP server.
  void handlePostRequest(HttpRequest request);

  /// Handle a request to upgrade to a WebSocket.
  void handleWebSocketRequest(HttpRequest request);
}

/// Instances of the class [HttpServer] implement a simple HTTP server. The
/// server:
///
/// - listens for an UPGRADE request in order to start an analysis server
/// - serves diagnostic information as html pages
class HttpAnalysisServer {
  /// Number of lines of print output to capture.
  static const int MAX_PRINT_BUFFER_LENGTH = 1000;

  /// An object that can handle either a WebSocket connection or a connection
  /// to the client over stdio.
  final AbstractSocketServer _socketServer;

  /// An object that can handle HTTP requests.
  late final AbstractHttpHandler _httpHandler = DiagnosticsSite(
    _socketServer,
    _printBuffer,
  );

  /// Future that is completed with the HTTP server once it is running.
  Future<HttpServer>? _serverFuture;

  /// Last PRINT_BUFFER_LENGTH lines printed.
  final List<String> _printBuffer = <String>[];

  /// Initialize a newly created HTTP server.
  HttpAnalysisServer(this._socketServer);

  /// Return the port this server is bound to.
  Future<int?> get boundPort async {
    return (await _serverFuture)?.port;
  }

  void close() {
    _serverFuture?.then((HttpServer server) {
      server.close();
    });
  }

  /// Record that the given line was printed out by the analysis server.
  void recordPrint(String line) {
    _printBuffer.add(line);
    if (_printBuffer.length > MAX_PRINT_BUFFER_LENGTH) {
      _printBuffer.removeRange(
        0,
        _printBuffer.length - MAX_PRINT_BUFFER_LENGTH,
      );
    }
  }

  /// Begin serving HTTP requests over the given port.
  Future<int?> serveHttp([int? initialPort]) async {
    if (_serverFuture != null) {
      return boundPort;
    }

    try {
      _serverFuture = HttpServer.bind(
        InternetAddress.loopbackIPv4,
        initialPort ?? 0,
      );

      var server = (await _serverFuture)!;
      _handleServer(server);
      return server.port;
    } catch (ignore) {
      // If we can't bind to the specified port, don't remember the broken
      // server.
      _serverFuture = null;

      return null;
    }
  }

  /// Attach a listener to a newly created HTTP server.
  void _handleServer(HttpServer httpServer) {
    httpServer.listen((HttpRequest request) {
      if (WebSocketTransformer.isUpgradeRequest(request) &&
          // For WebSockets, verify we're same origin (since the browser would
          // not).
          request.headers.value('origin') == request.requestedUri.origin) {
        _httpHandler.handleWebSocketRequest(request);
      } else if (request.method == 'GET') {
        _httpHandler.handleGetRequest(request);
      } else if (request.method == 'POST') {
        _httpHandler.handlePostRequest(request);
      } else {
        _returnUnknownRequest(request);
      }
    });
  }

  /// Return an error in response to an unrecognized request received by the
  /// HTTP server.
  void _returnUnknownRequest(HttpRequest request) {
    var response = request.response;
    response.statusCode = HttpStatus.notFound;
    response.headers.contentType = ContentType.text;
    response.write('Not found');
    response.close();
  }
}
