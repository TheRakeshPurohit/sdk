// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analysis_server_plugin/src/correction/performance.dart';
import 'package:collection/collection.dart';

String escape(String? text) => text == null ? '' : htmlEscape.convert(text);

String printMilliseconds(int value) => '$value ms';

String printPercentage(num value, [int fractionDigits = 1]) =>
    '${(value * 100).toStringAsFixed(fractionDigits)}%';

/// An entity that knows how to serve itself over http.
abstract class Page {
  final StringBuffer buf = StringBuffer();

  final String id;
  final String title;
  final String? description;

  Page(this.id, this.title, {this.description});

  String get path => '/$id';

  Future<void> asyncDiv(void Function() gen, {String? classes}) async {
    if (classes != null) {
      buf.writeln('<div class="$classes">');
    } else {
      buf.writeln('<div>');
    }
    // TODO(brianwilkerson): Determine if await is necessary, if so, change the
    // return type of [gen] to `Future<void>`.
    await (gen() as dynamic);
    buf.writeln('</div>');
  }

  void blankslate(String str) {
    div(() => buf.writeln(str), classes: 'blankslate');
  }

  String? contentDispositionString(Map<String, String> params) => null;

  ContentType contentType(Map<String, String> params) => ContentType.html;

  void div(void Function() gen, {String? classes}) {
    if (classes != null) {
      buf.writeln('<div class="$classes">');
    } else {
      buf.writeln('<div>');
    }
    gen();
    buf.writeln('</div>');
  }

  Future<String> generate(Map<String, String> params) async {
    buf.clear();
    await generatePage(params);
    return buf.toString();
  }

  Future<void> generatePage(Map<String, String> params);

  void h1(String text, {String? classes}) {
    if (classes != null) {
      buf.writeln('<h1 class="$classes">${escape(text)}</h1>');
    } else {
      buf.writeln('<h1>${escape(text)}</h1>');
    }
  }

  void h2(String text) {
    buf.writeln('<h2>${escape(text)}</h2>');
  }

  void h3(String text, {bool raw = false}) {
    buf.writeln('<h3>${raw ? text : escape(text)}</h3>');
  }

  void h4(String text, {bool raw = false}) {
    buf.writeln('<h4>${raw ? text : escape(text)}</h4>');
  }

  void inputList<T>(Iterable<T> items, void Function(T item) gen) {
    buf.writeln('<select size="8" style="width: 100%">');
    for (var item in items) {
      buf.write('<option>');
      gen(item);
      buf.write('</option>');
    }
    buf.writeln('</select>');
  }

  bool isCurrentPage(String pathToTest) => path == pathToTest;

  void p(String text, {String? style, bool raw = false, String? classes}) {
    var c = classes == null ? '' : ' class="$classes"';

    if (style != null) {
      buf.writeln('<p$c style="$style">${raw ? text : escape(text)}</p>');
    } else {
      buf.writeln('<p$c>${raw ? text : escape(text)}</p>');
    }
  }

  void pre(void Function() gen, {String? classes}) {
    if (classes != null) {
      buf.write('<pre class="$classes">');
    } else {
      buf.write('<pre>');
    }
    gen();
    buf.writeln('</pre>');
  }

  void prettyJson(Object? data) {
    const jsonEncoder = JsonEncoder.withIndent('  ');
    pre(() {
      buf.write(jsonEncoder.convert(data));
    });
  }

  void ul<T>(Iterable<T> items, void Function(T item) gen, {String? classes}) {
    buf.writeln('<ul${classes == null ? '' : ' class=$classes'}>');
    for (var item in items) {
      buf.write('<li>');
      gen(item);
      buf.write('</li>');
    }
    buf.writeln('</ul>');
  }
}

mixin PerformanceChartMixin on Page {
  void drawChart(List<RequestPerformance> items) {
    buf.writeln(
      '<div id="chart-div" style="width: 700px; height: 300px; padding-bottom: 30px;"></div>',
    );
    var rowData = StringBuffer();
    for (var i = items.length - 1; i >= 0; i--) {
      if (rowData.isNotEmpty) {
        rowData.write(',');
      }
      var latency = items[i].requestLatency ?? 0;
      var time = items[i].performance.elapsed.inMilliseconds;
      // label, latency, time
      // [' ', 21.0, 101.5]
      rowData.write("[' ', $latency, $time]");
    }
    buf.writeln('''
      <script type="text/javascript">
      google.charts.load('current', {'packages':['bar']});
      google.charts.setOnLoadCallback(drawChart);
      function drawChart() {
        var data = google.visualization.arrayToDataTable([
          [ 'Request', 'Latency', 'Time' ],
          $rowData
        ]);
        var options = {
          bars: 'vertical',
          vAxis: {format: 'decimal'},
          height: 300,
          isStacked: true,
          series: {
            0: { color: '#C0C0C0' },
            1: { color: '#4285f4' },
          }
        };
        var chart = new google.charts.Bar(document.getElementById('chart-div'));
        chart.draw(data, google.charts.Bar.convertOptions(options));
      }
      </script>
''');
  }
}

abstract interface class PostablePage {
  /// Handles a HTTP POST and returns a destination path to redirect to.
  Future<String> handlePost(Map<String, String> queryParameters);
}

/// Contains a collection of Pages.
abstract class Site {
  final String title;
  final List<Page> pages = [];

  Site(this.title);

  String get customCss => '';

  Page createExceptionPage(String message, StackTrace trace);

  Page createUnknownPage(String unknownPath);

  Future<void> handleGetRequest(HttpRequest request) async {
    var path = request.uri.path;
    if (path == '/') {
      unawaited(respondRedirect(request, pages.first.path));
      return;
    }

    await _tryHandleRequest(request, (response, queryParameters) async {
      var page = _getPage(path);
      if (page == null) {
        await respond(request, createUnknownPage(path), HttpStatus.notFound);
        return;
      }

      response.headers.contentType = page.contentType(queryParameters);
      var contentDispositionString = page.contentDispositionString(
        queryParameters,
      );
      if (contentDispositionString != null) {
        response.headers.add('Content-Disposition', contentDispositionString);
      }
      response.write(await page.generate(queryParameters));
    });
  }

  Future<void> handlePostRequest(HttpRequest request) async {
    var path = request.uri.path;

    await _tryHandleRequest(request, (response, queryParameters) async {
      var page = _getPage(path);
      if (page == null) {
        await respond(request, createUnknownPage(path), HttpStatus.notFound);
        return;
      } else if (page is PostablePage) {
        // For simplicitly we only support POSTs that redirect back to a GET at
        // the end and we use query parameters on the URL and don't process
        // encoded request bodies.
        var destinationPath = await (page as PostablePage).handlePost(
          queryParameters,
        );
        await respondRedirect(request, destinationPath);
      } else {
        throw 'Method not supported';
      }
    });
  }

  Future<void> handleWebSocketRequest(HttpRequest request) async {
    var path = request.uri.path;

    await _tryHandleRequest(request, (response, queryParameters) async {
      var page = _getPage(path);
      if (page == null) {
        await respond(request, createUnknownPage(path), HttpStatus.notFound);
        return;
      } else if (page is WebSocketPage) {
        var webSocket = await WebSocketTransformer.upgrade(request);
        await (page as WebSocketPage).handleWebSocket(webSocket);
        await webSocket.done;
      } else {
        throw 'Method not supported';
      }
    });
  }

  Future<void> respond(
    HttpRequest request,
    Page page, [
    int code = HttpStatus.ok,
  ]) async {
    var response = request.response;
    response.statusCode = code;
    response.headers.contentType = ContentType.html;
    response.write(await page.generate(request.uri.queryParameters));
    await response.close();
  }

  Future<void> respondJson(
    HttpRequest request,
    Map<String, Object> json, [
    int code = HttpStatus.ok,
  ]) async {
    var response = request.response;
    response.statusCode = code;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(json));
    await response.close();
  }

  Future<void> respondOk(
    HttpRequest request, {
    int code = HttpStatus.ok,
  }) async {
    if (request.headers.contentType?.subType == 'json') {
      return respondJson(request, {'success': true}, code);
    }

    var response = request.response;
    response.statusCode = code;
    await response.close();
  }

  Future<void> respondRedirect(HttpRequest request, String pathFragment) async {
    var response = request.response;
    response.statusCode = HttpStatus.movedTemporarily;
    await response.redirect(request.uri.resolve(pathFragment));
  }

  /// Finds the [Page] that should handle requests to [path].
  Page? _getPage(String path) {
    return pages.firstWhereOrNull((page) => page.path == path);
  }

  /// Calls the request handler [handler] and catches unhandled errors to return
  /// an exception page.
  Future<void> _tryHandleRequest(
    HttpRequest request,
    Future<void> Function(HttpResponse, Map<String, String>) handler,
  ) async {
    var response = request.response;
    var queryParameters = request.uri.queryParameters;

    try {
      await handler(response, queryParameters);
      unawaited(response.close());
      return;
    } catch (e, st) {
      try {
        await respond(
          request,
          createExceptionPage('$e', st),
          HttpStatus.internalServerError,
        );
      } catch (e, st) {
        var response = request.response;
        try {
          response.statusCode = HttpStatus.internalServerError;
          response.headers.contentType = ContentType.text;
          response.write('$e\n\n$st');
        } catch (_) {
          // We may fail to send the above if the request that errored had
          // already caused the HTTP headers to be flushed (this can happen
          // after a WebSocket upgrade, for example).
        }
        unawaited(response.close());
      }
    }
  }
}

abstract interface class WebSocketPage {
  /// Handles a WebSocket connection to the page.
  Future<void> handleWebSocket(WebSocket socket);
}
