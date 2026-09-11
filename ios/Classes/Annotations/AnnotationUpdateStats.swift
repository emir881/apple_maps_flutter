//
//  AnnotationUpdateStats.swift
//  apple_maps_flutter
//
//  Qibla teşhis eki — annotation güncelleme yolunun sayısal kanıtı.
//

import Foundation

/// `updateAnnotationOnMap`'in hangi yolu kaç kez seçtiğini sayar.
///
/// Neden gerekli: marker'ın YERİNDE mi güncellendiği yoksa silinip yeniden mi
/// eklendiği yalnız native tarafta belli — Dart sayaçları bunu göremez. Titreme
/// şikâyeti geldiğinde `rebuild` sayısının 0 olup olmadığı doğrudan cevap verir.
///
/// **Çıktı Dart'a PULL ile taşınır, log'a basılmaz.** Önce `print`, sonra
/// `NSLog` denendi; `flutter run` ikisini de yakalamıyor (yalnız Dart
/// `debugPrint`'ini dinliyor), bu yüzden hiçbir satır görünmedi. Dart tarafı
/// `camera#annoStats` kanalıyla anlık toplamları çeker ve kendi teşhis
/// sistemine yazar.
///
/// Bütün erişimler main thread'den olur: `updateAnnotationOnMap` MapKit
/// delegate'i ve Flutter method-channel handler'ı aynı thread'de çalışır.
final class AnnotationUpdateStats {
    static let shared = AnnotationUpdateStats()
    private init() {}

    private var inPlace = 0
    private var viewMissing = 0
    private var iconUpdates = 0
    private var rotationUpdates = 0
    private var coordinateUpdates = 0
    private var rebuilds = 0
    private var rebuildReasons: [String: Int] = [:]

    /// Marker yerinde güncellendi (sil-ekle YAPILMADI).
    func recordInPlace(icon: Bool = false, rotation: Bool = false, coordinate: Bool = false, viewMissing: Bool = false) {
        inPlace += 1
        if viewMissing { self.viewMissing += 1 }
        if icon { iconUpdates += 1 }
        if rotation { rotationUpdates += 1 }
        if coordinate { coordinateUpdates += 1 }
    }

    /// Marker silinip yeniden eklendi — titreme kaynağı. Sıfır olması beklenir.
    func recordRebuild(reason: String) {
        rebuilds += 1
        rebuildReasons[reason, default: 0] += 1
    }

    /// Toplamları döndürür ve sayaçları SIFIRLAR (pencere bazlı okuma).
    func snapshot() -> [String: Any] {
        let result: [String: Any] = [
            "inPlace": inPlace,
            "rebuilds": rebuilds,
            "rebuildReasons": rebuildReasons,
            "icon": iconUpdates,
            "rotation": rotationUpdates,
            "coordinate": coordinateUpdates,
            "viewMissing": viewMissing,
        ]
        inPlace = 0
        viewMissing = 0
        iconUpdates = 0
        rotationUpdates = 0
        coordinateUpdates = 0
        rebuilds = 0
        rebuildReasons.removeAll()
        return result
    }
}
