// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of apple_maps_flutter;

/// [Annotation] update events to be applied to the [AppleMap].
///
/// Used in [AppleMapController] when the map is updated.
class _AnnotationUpdates {
  /// Computes [_AnnotationUpdates] given previous and current [Annotation]s.
  _AnnotationUpdates.from(Set<Annotation>? previous, Set<Annotation>? current) {
    if (previous == null) {
      previous = Set<Annotation>.identity();
    }

    if (current == null) {
      current = Set<Annotation>.identity();
    }

    final Map<AnnotationId, Annotation> previousAnnotations =
        _keyByAnnotationId(previous);
    final Map<AnnotationId, Annotation> currentAnnotations =
        _keyByAnnotationId(current);

    final Set<AnnotationId> prevAnnotationIds =
        previousAnnotations.keys.toSet();
    final Set<AnnotationId> currentAnnotationIds =
        currentAnnotations.keys.toSet();

    Annotation idToCurrentAnnotation(AnnotationId id) {
      return currentAnnotations[id]!;
    }

    final Set<AnnotationId> _annotationIdsToRemove =
        prevAnnotationIds.difference(currentAnnotationIds);

    final Set<Annotation> _annotationsToAdd = currentAnnotationIds
        .difference(prevAnnotationIds)
        .map(idToCurrentAnnotation)
        .toSet();

    // Only annotations whose object actually changed are sent.
    //
    // WHY THIS FILTER EXISTS: the intersection used to go through untouched, so
    // EVERY annotation was serialized and pushed over the method channel on
    // every `didUpdateWidget` — regardless of whether anything about it moved.
    // A host that rebuilds its map widget from a sensor stream therefore paid a
    // full annotation update per sample. Measured in a Flutter host (iPhone 13,
    // 8 Sep 2026): 4005 map rebuilds in 185 s = 21.6 annotation pushes/second,
    // with the annotation objects themselves memoized and unchanged. That cost
    // is invisible to `FrameTiming`, which only sees the Dart build phase.
    //
    // `Annotation.==` cannot be used here: it compares `annotationId` only, so
    // it reports a moved annotation as equal. Identity is used instead, which
    // is exactly the contract a memoizing host relies on — return the same
    // instance while nothing changes, a new instance when something does.
    //
    // LIMITATION, stated rather than hidden: an annotation MUTATED IN PLACE
    // (same instance, different field) is skipped. `Annotation` is declared
    // `const`-constructible with final fields, so in-place mutation is not a
    // supported use anyway.
    final Set<Annotation> _annotationsToChange = currentAnnotationIds
        .intersection(prevAnnotationIds)
        .map(idToCurrentAnnotation)
        .where((Annotation current) =>
            !identical(previousAnnotations[current.annotationId], current))
        .toSet();

    annotationsToAdd = _annotationsToAdd;
    annotationIdsToRemove = _annotationIdsToRemove;
    annotationsToChange = _annotationsToChange;
  }

  late Set<Annotation> annotationsToAdd;
  late Set<AnnotationId> annotationIdsToRemove;
  late Set<Annotation> annotationsToChange;

  /// True when there is nothing for the platform side to do.
  ///
  /// With the identity filter above this is the common case for a host that
  /// rebuilds often, so the channel message is worth skipping entirely.
  bool get isEmpty =>
      annotationsToAdd.isEmpty &&
      annotationIdsToRemove.isEmpty &&
      annotationsToChange.isEmpty;

  Map<String, dynamic> _toMap() {
    final Map<String, dynamic> updateMap = <String, dynamic>{};

    void addIfNonNull(String fieldName, dynamic value) {
      if (value != null) {
        updateMap[fieldName] = value;
      }
    }

    addIfNonNull('annotationsToAdd', _serializeAnnotationSet(annotationsToAdd));
    addIfNonNull(
        'annotationsToChange', _serializeAnnotationSet(annotationsToChange));
    addIfNonNull(
        'annotationIdsToRemove',
        annotationIdsToRemove
            .map<dynamic>((AnnotationId m) => m.value)
            .toList());

    return updateMap;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _AnnotationUpdates) return false;
    final _AnnotationUpdates typedOther = other;
    return setEquals(annotationsToAdd, typedOther.annotationsToAdd) &&
        setEquals(annotationIdsToRemove, typedOther.annotationIdsToRemove) &&
        setEquals(annotationsToChange, typedOther.annotationsToChange);
  }

  @override
  int get hashCode =>
      Object.hash(annotationsToAdd, annotationIdsToRemove, annotationsToChange);

  @override
  String toString() {
    return '_AnnotationUpdates{annotationsToAdd: $annotationsToAdd, '
        'annotationIdsToRemove: $annotationIdsToRemove, '
        'annotationsToChange: $annotationsToChange}';
  }
}
