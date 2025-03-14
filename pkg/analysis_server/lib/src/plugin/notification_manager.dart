// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:analysis_server/protocol/protocol_generated.dart' as server;
import 'package:analysis_server/src/channel/channel.dart';
import 'package:analysis_server/src/plugin/result_collector.dart';
import 'package:analysis_server/src/plugin/result_converter.dart';
import 'package:analysis_server/src/plugin/result_merger.dart';
import 'package:analyzer_plugin/protocol/protocol.dart' as plugin;
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_constants.dart' as plugin;
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as plugin;
import 'package:analyzer_plugin/src/utilities/client_uri_converter.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

/// The object used to coordinate the results of notifications from the analysis
/// server and multiple plugins.
abstract class AbstractNotificationManager {
  /// The identifier used to identify results from the server.
  static const String serverId = 'server';

  /// The current URI converter used for translating URIs/Paths for the
  /// server-client side of communication.
  ClientUriConverter? uriConverter;

  /// The path context.
  final Context _pathContext;

  /// A list of the paths of files and directories that are included for
  /// analysis.
  List<String> _includedPaths = <String>[];

  /// A list of the paths of files and directories that are excluded from
  /// analysis.
  List<String> _excludedPaths = <String>[];

  /// The current set of subscriptions to which the client has subscribed.
  Map<server.AnalysisService, Set<String>> _currentSubscriptions =
      <server.AnalysisService, Set<String>>{};

  /// The collector being used to collect the analysis errors from the plugins.
  // TODO(brianwilkerson): Consider the possibility of not passing the predicate
  //  in to the collector, but instead to the testing in this class.
  late final ResultCollector<List<AnalysisError>> errors =
      ResultCollector<List<AnalysisError>>(serverId, predicate: _isIncluded);

  /// The collector being used to collect the folding regions from the plugins.
  final ResultCollector<List<FoldingRegion>> folding;

  /// The collector being used to collect the highlight regions from the
  /// plugins.
  final ResultCollector<List<HighlightRegion>> highlights;

  /// The collector being used to collect the navigation parameters from the
  /// plugins.
  final ResultCollector<server.AnalysisNavigationParams> _navigation;

  /// The collector being used to collect the occurrences from the plugins.
  final ResultCollector<List<Occurrences>> _occurrences;

  /// The collector being used to collect the outlines from the plugins.
  final ResultCollector<List<Outline>> _outlines;

  /// The object used to convert results.
  final ResultConverter _converter = ResultConverter();

  /// The object used to merge results.
  final ResultMerger merger = ResultMerger();

  /// Whether the plugin isolate is currently analyzing, as per its last status
  /// notification.
  bool pluginStatusAnalyzing = false;

  /// The controller that is notified when analysis status changes.
  final StreamController<bool> _analysisStatusChangesController =
      StreamController.broadcast();

  /// Initialize a newly created notification manager.
  AbstractNotificationManager(this._pathContext)
    : folding = ResultCollector<List<FoldingRegion>>(serverId),
      highlights = ResultCollector<List<HighlightRegion>>(serverId),
      _navigation = ResultCollector<server.AnalysisNavigationParams>(serverId),
      _occurrences = ResultCollector<List<Occurrences>>(serverId),
      _outlines = ResultCollector<List<Outline>>(serverId);

  /// The Stream of analysis statuses from the plugin isolate.
  ///
  /// Each value emitted represents whether the plugin isolate is analyzing or
  /// not, as per each status notification.
  Stream<bool> get pluginAnalysisStatusChanges =>
      _analysisStatusChangesController.stream;

  /// Handles a plugin error.
  ///
  /// This amounts to notifying the client, and setting the 'is analyzing'
  /// status to `false`.
  ///
  /// The caller is responsible for logging the error with the instrumentation
  /// service.
  void handlePluginError(String message) {
    _analysisStatusChangesController.add(false /* isAnalyzing */);
    pluginStatusAnalyzing = false;

    sendPluginError(message);
  }

  /// Handle the given [notification] from the plugin with the given [pluginId].
  void handlePluginNotification(
    String pluginId,
    plugin.Notification notification,
  ) {
    var event = notification.event;
    switch (event) {
      case plugin.ANALYSIS_NOTIFICATION_ERRORS:
        var params = plugin.AnalysisErrorsParams.fromNotification(notification);
        recordAnalysisErrors(pluginId, params.file, params.errors);
      case plugin.ANALYSIS_NOTIFICATION_FOLDING:
        var params = plugin.AnalysisFoldingParams.fromNotification(
          notification,
        );
        recordFoldingRegions(pluginId, params.file, params.regions);
      case plugin.ANALYSIS_NOTIFICATION_HIGHLIGHTS:
        var params = plugin.AnalysisHighlightsParams.fromNotification(
          notification,
        );
        recordHighlightRegions(pluginId, params.file, params.regions);
      case plugin.ANALYSIS_NOTIFICATION_NAVIGATION:
        var params = plugin.AnalysisNavigationParams.fromNotification(
          notification,
        );
        recordNavigationParams(
          pluginId,
          params.file,
          _converter.convertAnalysisNavigationParams(params),
        );
      case plugin.ANALYSIS_NOTIFICATION_OCCURRENCES:
        var params = plugin.AnalysisOccurrencesParams.fromNotification(
          notification,
        );
        recordOccurrences(pluginId, params.file, params.occurrences);
      case plugin.ANALYSIS_NOTIFICATION_OUTLINE:
        var params = plugin.AnalysisOutlineParams.fromNotification(
          notification,
        );
        recordOutlines(pluginId, params.file, params.outline);
      case plugin.PLUGIN_NOTIFICATION_ERROR:
        sendPluginErrorNotification(notification);
      case plugin.PLUGIN_NOTIFICATION_STATUS:
        _setPluginStatus(notification);
    }
  }

  /// Record error information from the plugin with the given [pluginId] for the
  /// file with the given [filePath].
  void recordAnalysisErrors(
    String pluginId,
    String filePath,
    List<AnalysisError> errorData,
  ) {
    if (errors.isCollectingFor(filePath)) {
      errors.putResults(filePath, pluginId, errorData);
      var unmergedErrors = errors.getResults(filePath);
      var mergedErrors = merger.mergeAnalysisErrors(unmergedErrors);
      sendAnalysisErrors(filePath, mergedErrors);
    }
  }

  /// Record folding information from the plugin with the given [pluginId] for
  /// the file with the given [filePath].
  void recordFoldingRegions(
    String pluginId,
    String filePath,
    List<FoldingRegion> foldingData,
  ) {
    if (folding.isCollectingFor(filePath)) {
      folding.putResults(filePath, pluginId, foldingData);
      var unmergedFolding = folding.getResults(filePath);
      var mergedFolding = merger.mergeFoldingRegions(unmergedFolding);
      sendFoldingRegions(filePath, mergedFolding);
    }
  }

  /// Record highlight information from the plugin with the given [pluginId] for
  /// the file with the given [filePath].
  void recordHighlightRegions(
    String pluginId,
    String filePath,
    List<HighlightRegion> highlightData,
  ) {
    if (highlights.isCollectingFor(filePath)) {
      highlights.putResults(filePath, pluginId, highlightData);
      var unmergedHighlights = highlights.getResults(filePath);
      var mergedHighlights = merger.mergeHighlightRegions(unmergedHighlights);
      sendHighlightRegions(filePath, mergedHighlights);
    }
  }

  /// Record navigation information from the plugin with the given [pluginId]
  /// for the file with the given [filePath].
  void recordNavigationParams(
    String pluginId,
    String filePath,
    server.AnalysisNavigationParams navigationData,
  ) {
    if (_navigation.isCollectingFor(filePath)) {
      _navigation.putResults(filePath, pluginId, navigationData);
      var unmergedNavigations = _navigation.getResults(filePath);
      var mergedNavigations = merger.mergeNavigation(unmergedNavigations);
      if (mergedNavigations != null) {
        sendNavigations(mergedNavigations);
      }
    }
  }

  /// Record occurrences information from the plugin with the given [pluginId]
  /// for the file with the given [filePath].
  void recordOccurrences(
    String pluginId,
    String filePath,
    List<Occurrences> occurrencesData,
  ) {
    if (_occurrences.isCollectingFor(filePath)) {
      _occurrences.putResults(filePath, pluginId, occurrencesData);
      var unmergedOccurrences = _occurrences.getResults(filePath);
      var mergedOccurrences = merger.mergeOccurrences(unmergedOccurrences);
      sendOccurrences(filePath, mergedOccurrences);
    }
  }

  /// Record outline information from the plugin with the given [pluginId] for
  /// the file with the given [filePath].
  void recordOutlines(
    String pluginId,
    String filePath,
    List<Outline> outlineData,
  ) {
    if (_outlines.isCollectingFor(filePath)) {
      _outlines.putResults(filePath, pluginId, outlineData);
      var unmergedOutlines = _outlines.getResults(filePath);
      var mergedOutlines = merger.mergeOutline(unmergedOutlines);
      sendOutlines(filePath, mergedOutlines);
    }
  }

  /// Sends errors for a file to the client.
  @visibleForOverriding
  void sendAnalysisErrors(String filePath, List<AnalysisError> mergedErrors);

  /// Sends folding regions for a file to the client.
  @visibleForOverriding
  void sendFoldingRegions(String filePath, List<FoldingRegion> mergedFolding);

  /// Sends highlight regions for a file to the client.
  @visibleForOverriding
  void sendHighlightRegions(
    String filePath,
    List<HighlightRegion> mergedHighlights,
  );

  /// Sends navigation regions for a file to the client.
  @visibleForOverriding
  void sendNavigations(server.AnalysisNavigationParams mergedNavigations);

  /// Sends occurrences for a file to the client.
  @visibleForOverriding
  void sendOccurrences(String filePath, List<Occurrences> mergedOccurrences);

  /// Sends outlines for a file to the client.
  @visibleForOverriding
  void sendOutlines(String filePath, List<Outline> mergedOutlines);

  @visibleForOverriding
  void sendPluginError(String message);

  /// Sends plugin errors to the client.
  @visibleForOverriding
  void sendPluginErrorNotification(plugin.Notification notification);

  /// Set the lists of [included] and [excluded] files.
  void setAnalysisRoots(List<String> included, List<String> excluded) {
    _includedPaths = included;
    _excludedPaths = excluded;
  }

  /// Set the current subscriptions to the given set of [newSubscriptions].
  void setSubscriptions(
    Map<server.AnalysisService, Set<String>> newSubscriptions,
  ) {
    /// Returns the collector associated with the given service, or `null` if
    /// the service is not handled by this manager.
    ResultCollector<Object?>? collectorFor(server.AnalysisService service) {
      return switch (service) {
        server.AnalysisService.FOLDING => folding,
        server.AnalysisService.HIGHLIGHTS => highlights,
        server.AnalysisService.NAVIGATION => _navigation,
        server.AnalysisService.OCCURRENCES => _occurrences,
        server.AnalysisService.OUTLINE => _outlines,
        _ => null,
      };
    }

    Set<server.AnalysisService> services = HashSet<server.AnalysisService>();
    services.addAll(_currentSubscriptions.keys);
    services.addAll(newSubscriptions.keys);
    for (var service in services) {
      var collector = collectorFor(service);
      if (collector != null) {
        var currentPaths = _currentSubscriptions[service];
        var newPaths = newSubscriptions[service];
        if (currentPaths == null) {
          if (newPaths == null) {
            // This should not happen.
            return;
          }
          // All of the [newPaths] need to be added.
          for (var filePath in newPaths) {
            collector.startCollectingFor(filePath);
          }
        } else if (newPaths == null) {
          // All of the [currentPaths] need to be removed.
          for (var filePath in currentPaths) {
            collector.stopCollectingFor(filePath);
          }
        } else {
          // Compute the difference of the two sets.
          for (var filePath in newPaths) {
            if (!currentPaths.contains(filePath)) {
              collector.startCollectingFor(filePath);
            }
          }
          for (var filePath in currentPaths) {
            if (!newPaths.contains(filePath)) {
              collector.stopCollectingFor(filePath);
            }
          }
        }
      }
    }
    _currentSubscriptions = newSubscriptions;
  }

  /// Return `true` if errors should be collected for the file with the given
  /// [path] (because it is being analyzed).
  bool _isIncluded(String path) {
    bool isIncluded() {
      for (var includedPath in _includedPaths) {
        if (_pathContext.isWithin(includedPath, path) ||
            _pathContext.equals(includedPath, path)) {
          return true;
        }
      }
      return false;
    }

    bool isExcluded() {
      for (var excludedPath in _excludedPaths) {
        if (_pathContext.isWithin(excludedPath, path)) {
          return true;
        }
      }
      return false;
    }

    // TODO(brianwilkerson): Return false if error notifications are globally
    // disabled.
    return isIncluded() && !isExcluded();
  }

  /// Records a status notification from the analyzer plugin.
  void _setPluginStatus(plugin.Notification notification) {
    var params = plugin.PluginStatusParams.fromNotification(notification);
    var analysis = params.analysis;
    if (analysis == null) {
      return;
    }
    var isAnalyzing = analysis.isAnalyzing;
    _analysisStatusChangesController.add(isAnalyzing);
    pluginStatusAnalyzing = isAnalyzing;
  }
}

class NotificationManager extends AbstractNotificationManager {
  /// The identifier used to identify results from the server.
  static const String serverId = AbstractNotificationManager.serverId;

  /// The channel used to send notifications to the client.
  final ServerCommunicationChannel _channel;

  /// Initialize a newly created notification manager.
  NotificationManager(this._channel, super.pathContext);

  /// Sends errors for a file to the client.
  @override
  void sendAnalysisErrors(String filePath, List<AnalysisError> mergedErrors) {
    _channel.sendNotification(
      server.AnalysisErrorsParams(
        filePath,
        mergedErrors,
      ).toNotification(clientUriConverter: uriConverter),
    );
  }

  /// Sends folding regions for a file to the client.
  @override
  void sendFoldingRegions(String filePath, List<FoldingRegion> mergedFolding) {
    _channel.sendNotification(
      server.AnalysisFoldingParams(
        filePath,
        mergedFolding,
      ).toNotification(clientUriConverter: uriConverter),
    );
  }

  /// Sends highlight regions for a file to the client.
  @override
  void sendHighlightRegions(
    String filePath,
    List<HighlightRegion> mergedHighlights,
  ) {
    _channel.sendNotification(
      server.AnalysisHighlightsParams(
        filePath,
        mergedHighlights,
      ).toNotification(clientUriConverter: uriConverter),
    );
  }

  /// Sends navigation regions for a file to the client.
  @override
  void sendNavigations(server.AnalysisNavigationParams mergedNavigations) {
    _channel.sendNotification(
      mergedNavigations.toNotification(clientUriConverter: uriConverter),
    );
  }

  /// Sends occurrences for a file to the client.
  @override
  void sendOccurrences(String filePath, List<Occurrences> mergedOccurrences) {
    _channel.sendNotification(
      server.AnalysisOccurrencesParams(
        filePath,
        mergedOccurrences,
      ).toNotification(clientUriConverter: uriConverter),
    );
  }

  /// Sends outlines for a file to the client.
  @override
  void sendOutlines(String filePath, List<Outline> mergedOutlines) {
    _channel.sendNotification(
      server.AnalysisOutlineParams(
        filePath,
        server.FileKind.LIBRARY,
        mergedOutlines[0],
      ).toNotification(clientUriConverter: uriConverter),
    );
  }

  @override
  void sendPluginError(String message) {
    _channel.sendNotification(
      server.ServerPluginErrorParams(
        message,
      ).toNotification(clientUriConverter: uriConverter),
    );
  }

  /// Sends plugin errors to the client.
  @override
  void sendPluginErrorNotification(plugin.Notification notification) {
    var params = plugin.PluginErrorParams.fromNotification(
      notification,
      // No uriConverter here because it's from a plugin.
    );
    // TODO(brianwilkerson): There is no indication for the client as to the
    // fact that the error came from a plugin, let alone which plugin it
    // came from. We should consider whether we really want to send them to
    // the client.
    _channel.sendNotification(
      server.ServerErrorParams(
        params.isFatal,
        params.message,
        params.stackTrace,
      ).toNotification(clientUriConverter: uriConverter),
    );
  }
}
