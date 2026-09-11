// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of apple_maps_flutter;

/// Controller for a single AppleMap instance running on the host platform.
class AppleMapController {
  AppleMapController._(
    this.channel,
    CameraPosition initialCameraPosition,
    this._appleMapState,
  ) {
    channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<AppleMapController> init(
    int id,
    CameraPosition initialCameraPosition,
    _AppleMapState appleMapState,
  ) async {
    final MethodChannel channel = MethodChannel(
      'apple_maps_plugin.luisthein.de/apple_maps_$id',
    );
    // await channel.invokeMethod<void>('map#waitForMap');
    return AppleMapController._(channel, initialCameraPosition, appleMapState);
  }

  @visibleForTesting
  final MethodChannel channel;

  final _AppleMapState _appleMapState;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'camera#onMoveStarted':
        _appleMapState.widget.onCameraMoveStarted?.call();
        break;
      case 'camera#onMove':
        _appleMapState.widget.onCameraMove?.call(
          CameraPosition.fromMap(call.arguments['position'])!,
        );
        break;
      case 'camera#onIdle':
        _appleMapState.widget.onCameraIdle?.call();
        break;
      case 'annotation#onTap':
        _appleMapState.onAnnotationTap(call.arguments['annotationId']);
        break;
      case 'polyline#onTap':
        _appleMapState.onPolylineTap(call.arguments['polylineId']);
        break;
      case 'polygon#onTap':
        _appleMapState.onPolygonTap(call.arguments['polygonId']);
        break;
      case 'circle#onTap':
        _appleMapState.onCircleTap(call.arguments['circleId']);
        break;
      case 'annotation#onDragEnd':
        _appleMapState.onAnnotationDragEnd(
          call.arguments['annotationId'],
          LatLng._fromJson(call.arguments['position'])!,
        );
        break;
      case 'annotation#rotate':
        _appleMapState.onAnnotationRotate(
          call.arguments['annotationId'],
          call.arguments['rotationAngle']!,
        );
        break;
      case 'infoWindow#onTap':
        _appleMapState.onInfoWindowTap(call.arguments['annotationId']);
        break;
      case 'map#onTap':
        _appleMapState.onTap(LatLng._fromJson(call.arguments['position'])!);
        break;
      case 'map#onLongPress':
        _appleMapState.onLongPress(
          LatLng._fromJson(call.arguments['position'])!,
        );
        break;
      default:
        throw MissingPluginException();
    }
  }

  /// Updates configuration options of the map user interface.
  ///
  /// Change listeners are notified once the update has been made on the
  /// platform side.
  ///
  /// The returned [Future] completes after listeners have been notified.
  Future<void> _updateMapOptions(Map<String, dynamic> optionsUpdate) async {
    await channel.invokeMethod<void>('map#update', <String, dynamic>{
      'options': optionsUpdate,
    });
  }

  /// Updates annotation configuration.
  ///
  /// Change listeners are notified once the update has been made on the
  /// platform side.
  ///
  /// The returned [Future] completes after listeners have been notified.
  Future<void> _updateAnnotations(_AnnotationUpdates annotationUpdates) async {
    await channel.invokeMethod<void>(
      'annotations#update',
      annotationUpdates._toMap(),
    );
  }

  /// Updates polyline configuration.
  ///
  /// Change listeners are notified once the update has been made on the
  /// platform side.
  ///
  /// The returned [Future] completes after listeners have been notified.
  Future<void> _updatePolylines(_PolylineUpdates polylineUpdates) async {
    await channel.invokeMethod<void>(
      'polylines#update',
      polylineUpdates._toMap(),
    );
  }

  /// Updates polygon configuration.
  ///
  /// Change listeners are notified once the update has been made on the
  /// platform side.
  ///
  /// The returned [Future] completes after listeners have been notified.
  Future<void> _updatePolygons(_PolygonUpdates polygonUpdates) async {
    await channel.invokeMethod<void>(
      'polygons#update',
      polygonUpdates._toMap(),
    );
  }

  /// Updates circle configuration.
  ///
  /// Change listeners are notified once the update has been made on the
  /// platform side.
  ///
  /// The returned [Future] completes after listeners have been notified.
  Future<void> _updateCircles(_CircleUpdates circleUpdates) async {
    await channel.invokeMethod<void>('circles#update', circleUpdates._toMap());
  }

  /// Starts an animated change of the map camera position.
  ///
  /// The returned [Future] completes after the change has been started on the
  /// platform side.
  Future<void> animateCamera(CameraUpdate cameraUpdate) async {
    await channel.invokeMethod<void>('camera#animate', <String, dynamic>{
      'cameraUpdate': cameraUpdate._toJson(),
    });
  }

  /// Programmatically show the Info Window for a [Marker].
  ///
  /// The `markerId` must match one of the markers on the map.
  /// An invalid `markerId` triggers an "Invalid markerId" error.
  ///
  /// * See also:
  ///   * [hideMarkerInfoWindow] to hide the Info Window.
  ///   * [isMarkerInfoWindowShown] to check if the Info Window is showing.
  Future<void> showMarkerInfoWindow(AnnotationId annotationId) {
    return channel.invokeMethod<void>(
      'annotations#showInfoWindow',
      <String, String>{'annotationId': annotationId.value},
    );
  }

  /// Programmatically hide the Info Window for a [Marker].
  ///
  /// The `markerId` must match one of the markers on the map.
  /// An invalid `markerId` triggers an "Invalid markerId" error.
  ///
  /// * See also:
  ///   * [showMarkerInfoWindow] to show the Info Window.
  ///   * [isMarkerInfoWindowShown] to check if the Info Window is showing.
  Future<void> hideMarkerInfoWindow(AnnotationId annotationId) {
    return channel.invokeMethod<void>(
      'annotations#hideInfoWindow',
      <String, String>{'annotationId': annotationId.value},
    );
  }

  /// Returns `true` when the [InfoWindow] is showing, `false` otherwise.
  ///
  /// The `markerId` must match one of the markers on the map.
  /// An invalid `markerId` triggers an "Invalid markerId" error.
  ///
  /// * See also:
  ///   * [showMarkerInfoWindow] to show the Info Window.
  ///   * [hideMarkerInfoWindow] to hide the Info Window.
  Future<bool?> isMarkerInfoWindowShown(AnnotationId annotationId) {
    return channel.invokeMethod<bool>(
      'annotations#isInfoWindowShown',
      <String, String>{'annotationId': annotationId.value},
    );
  }

  /// Changes the map camera position.
  ///
  /// The returned [Future] completes after the change has been made on the
  /// platform side.
  Future<void> moveCamera(CameraUpdate cameraUpdate) async {
    await channel.invokeMethod<void>('camera#move', <String, dynamic>{
      'cameraUpdate': cameraUpdate._toJson(),
    });
  }

  /// Rotates the map to [heading] degrees clockwise from true north, leaving
  /// the zoom level untouched.
  ///
  /// Prefer this over [moveCamera] whenever only the rotation should change.
  /// A [CameraPosition] always carries a zoom level, and the platform's read
  /// and write paths for zoom are not exact inverses, so re-sending the level
  /// on every rotation makes the scale creep away from what the user picked.
  /// This call never sends a zoom level at all — the native side keeps the
  /// camera's current altitude as is.
  ///
  /// Pass [target] to recenter the map in the same camera write; omit it to
  /// rotate around the current center.
  ///
  /// Set [animated] to `true` for a short animated transition. Note that an
  /// animated call also interrupts an in-flight camera animation, which a
  /// non-animated one does not.
  ///
  /// Returns `true` when the heading was applied, and `false` when the native
  /// camera was not in a usable state — most commonly because the map view is
  /// currently laid out with zero size. Callers that must not miss a rotation
  /// should treat `false` as a signal to retry or fall back to [moveCamera].
  Future<bool> setHeading(
    double heading, {
    LatLng? target,
    bool animated = false,
  }) async {
    // Returns false instead of throwing when the host runs a plugin binary
    // without this method: the caller can then fall back or skip the write,
    // whereas a MissingPluginException escaping an unawaited compass callback
    // becomes an unhandled async error and tears down the rotation path.
    final bool? applied;
    try {
      applied = await channel
          .invokeMethod<bool>('camera#setHeading', <String, dynamic>{
            'heading': heading,
            if (target != null) 'target': target._toJson(),
            'animated': animated,
          });
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
    return applied ?? false;
  }

  /// Diagnostics: how the native side has been updating annotations since the
  /// last call, and resets those counters.
  ///
  /// Keys: `inPlace`, `rebuilds`, `rebuildReasons`, `icon`, `rotation`,
  /// `coordinate`, `viewMissing`. `rebuilds` counts annotations that had to be
  /// removed and re-added — the path that makes a marker visibly blink — so a
  /// non-zero value is the signal to look at.
  ///
  /// This is pulled rather than logged because native stdout does not reach
  /// `flutter run`, which only listens to Dart's own logging.
  Future<Map<String, dynamic>?> annotationStats() async {
    // A diagnostic must never be able to break the feature it measures: an
    // older plugin binary (or a host that has not recompiled the native side)
    // answers this channel call with FlutterMethodNotImplemented, which
    // surfaces as MissingPluginException. Swallow it and report "no stats"
    // instead of propagating into the caller's camera path.
    final Map<Object?, Object?>? raw;
    try {
      raw = await channel.invokeMethod<Map<Object?, Object?>>(
        'camera#annoStats',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    if (raw == null) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> rotateAnnotation({
    required String annotationId,
    required double degree,
    double? durationInSeconds,
  }) async {
    await channel.invokeMethod<void>('annotation#rotate', <String, dynamic>{
      'annotation': {
        'id': annotationId,
        'rotation': degree,
        'duration': durationInSeconds ?? 0,
      },
    });
  }

  /// Returns the current zoomLevel.
  Future<double?> getZoomLevel() async {
    return channel.invokeMethod<double>('camera#getZoomLevel');
  }

  /// The camera's actual heading in degrees, read straight off `MKMapCamera`.
  ///
  /// Diagnostic counterpart to [setHeading]. `setCamera(_:animated:)` has no
  /// completion handler, so a write returns before the map has moved — and an
  /// animated write can be cancelled by the next write after covering only a
  /// fraction of the arc. Comparing the commanded angle with this value is the
  /// only way to tell a rotation that happened from one that did not.
  ///
  /// Returns `null` when the platform does not implement it (older binary), so
  /// a diagnostic can never break the feature it measures.
  /// The zoom level the camera is ACTUALLY at, and the altitude it came from.
  ///
  /// Prefer this over [getZoomLevel] for anything that makes a decision:
  /// `getZoomLevel` returns `calculatedZoomLevel`, which is derived from the
  /// visible region's bounding box and therefore changes as the map ROTATES
  /// even though the camera has not moved. This one is derived from
  /// `camera.altitude` by inverting the write path's own function, so it is
  /// heading-independent and on the same scale as a commanded level.
  ///
  /// Returns `null` on an older platform binary or before the view has bounds,
  /// so a caller can fall back instead of acting on a wrong number.
  /// Returns `{'zoom': …, 'altitude': …}` — a plain map, not a record: this
  /// package's SDK constraint predates Dart 3, so records do not compile here.
  Future<Map<String, double>?> actualZoom() async {
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('camera#actualZoom');
      if (res == null) return null;
      final zoom = (res['zoom'] as num?)?.toDouble();
      final altitude = (res['altitude'] as num?)?.toDouble();
      if (zoom == null || altitude == null) return null;
      if (!zoom.isFinite || !altitude.isFinite) return null;
      // The centre rides along (see the native handler). It was being DROPPED
      // here: the platform side started returning `lat`/`lng` but this method
      // only copied `zoom` and `altitude`, so a host asking "is the map still
      // centred on X" silently got nothing and fell back to gesture data.
      final out = <String, double>{'zoom': zoom, 'altitude': altitude};
      final lat = (res['lat'] as num?)?.toDouble();
      final lng = (res['lng'] as num?)?.toDouble();
      if (lat != null && lng != null && lat.isFinite && lng.isFinite) {
        out['lat'] = lat;
        out['lng'] = lng;
      }
      return out;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// The camera's current heading and centre coordinate.
  ///
  /// Returns `{'heading': deg, 'lat': .., 'lng': ..}`, or `null` when the
  /// platform side is unavailable.
  ///
  /// The centre travels with the heading because `onCameraMove` cannot be
  /// trusted to report panning: it is fed by native gesture recognizers that a
  /// Flutter gesture team can win. Read the camera when you need the truth.
  Future<Map<String, double>?> getHeading() async {
    try {
      // Tolerates the pre-centre binary, which returned a bare heading double.
      // Plugin Dart and Swift ship together, but an incremental host build can
      // load a stale framework; a type error here would take the caller down.
      final dynamic raw = await channel.invokeMethod<dynamic>('camera#getHeading');
      if (raw == null) return null;
      if (raw is num) return <String, double>{'heading': raw.toDouble()};
      if (raw is! Map) return null;
      final Map<dynamic, dynamic> res = raw;
      final out = <String, double>{};
      for (final entry in res.entries) {
        final value = entry.value;
        if (value is num) out[entry.key.toString()] = value.toDouble();
      }
      return out;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Kameranın hem döndürülebildiği hem de istenen uzaklıkta kaldığı en uzak
  /// (en küçük) zoom seviyesi.
  ///
  /// MapKit uzak ölçekte ya `heading`'i uygulamaz ya da uygular ama kamerayı
  /// kendisi içeri çeker. İki kriter birlikte aranır. Eşik ekran yüksekliğine
  /// bağlı olduğundan sabit gömülemez — çalışma anında ölçülür (ikili arama;
  /// ekranda ara durum çizilmez, kamera ölçüm sonunda geri konur).
  ///
  /// [fromZoom]: taramanın başlayacağı en uzak zoom (uygulamanın alt sınırı).
  /// Dönen map: `zoom` (bulunan seviye, hiçbiri tutmuyorsa -1), `headOk`/`altOk`
  /// (bulunan seviyenin bayrakları), `belowHead`/`belowAlt` (bir alt seviyede
  /// hangi kriterin düştüğü — teşhis).
  Future<Map<String, dynamic>?> maxRotatableZoom({
    double fromZoom = 1.0,
  }) async {
    return channel.invokeMapMethod<String, dynamic>(
      'qibla#maxRotatableZoom',
      <String, dynamic>{'fromZoom': fromZoom},
    );
  }

  /// Return [LatLngBounds] defining the region that is visible in a map.
  Future<LatLngBounds> getVisibleRegion() async {
    final Map<String, dynamic>? latLngBounds = await channel
        .invokeMapMethod<String, dynamic>('map#getVisibleRegion');
    final LatLng southwest = LatLng._fromJson(latLngBounds?['southwest'])!;
    final LatLng northeast = LatLng._fromJson(latLngBounds?['northeast'])!;

    return LatLngBounds(northeast: northeast, southwest: southwest);
  }

  /// A projection is used to translate between on screen location and geographic coordinates.
  /// Screen location is in screen pixels (not display pixels) with respect to the top left corner
  /// of the map, not necessarily of the whole screen.
  Future<Offset?> getScreenCoordinate(LatLng latLng) async {
    final point = await channel.invokeMapMethod<String, dynamic>(
      'camera#convert',
      <String, dynamic>{
        'annotation': [latLng.latitude, latLng.longitude],
      },
    );
    if (point != null && !point.containsKey('point')) {
      return null;
    }
    final doubles = List<double>.from(point?['point']);
    return Offset(doubles.first, doubles.last);
  }

  /// Returns the image bytes of the map
  Future<Uint8List?> takeSnapshot([
    SnapshotOptions snapshotOptions = const SnapshotOptions(),
  ]) {
    return channel.invokeMethod<Uint8List>(
      'map#takeSnapshot',
      snapshotOptions._toMap(),
    );
  }
}
