//
//  AnnotationController.swift
//  apple_maps_flutter
//
//  Created by Luis Thein on 09.09.19.
//

import Foundation
import MapKit

extension AppleMapController: AnnotationDelegate {

    func getAnnotationView(annotation: FlutterAnnotation) -> MKAnnotationView {
        let identifier: String = annotation.id
        var annotationView = self.mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        let oldflutterAnnoation = annotationView?.annotation as? FlutterAnnotation
        if annotationView == nil || oldflutterAnnoation?.icon.iconType != annotation.icon.iconType {
            if annotation.icon.iconType == IconType.PIN {
                annotationView = getPinAnnotationView(annotation: annotation, id: identifier)
            } else if annotation.icon.iconType == IconType.MARKER {
                annotationView = getMarkerAnnotationView(annotation: annotation, id: identifier)
            } else if annotation.icon.iconType == .CUSTOM_FROM_ASSET || annotation.icon.iconType == .CUSTOM_FROM_BYTES {
                annotationView = getCustomAnnotationView(annotation: annotation, id: identifier)
            }
        }
        guard annotationView != nil else {
            print("annotation view is nil")
            return MKAnnotationView()
        
        }
        annotationView!.annotation = annotation
        // If annotation is not visible set alpha to 0 and don't let the user interact with it
        if !annotation.isVisible! {
            annotationView!.canShowCallout = false
            annotationView!.alpha = CGFloat(0.0)
            annotationView!.isDraggable = false
            return annotationView!
        }
        if annotation.icon.iconType != .MARKER {
            initInfoWindow(annotation: annotation, annotationView: annotationView!)
            if annotation.icon.iconType != .PIN {
                let x = (0.5 - annotation.anchor.x) * Double(annotationView!.frame.size.width)
                let y = (0.5 - annotation.anchor.y) * Double(annotationView!.frame.size.height)
                annotationView!.centerOffset = CGPoint(x: x, y: y)
            }
        }
        annotationView!.canShowCallout = true
        annotationView!.alpha = CGFloat(annotation.alpha ?? 1.00)
        // Rotation VERİLDİYSE transform'u koşulsuz yaz (0 dahil): view
        // `dequeueReusableAnnotationView` ile yeniden kullanıldığında önceki açı
        // takılı kalıyordu — eski kod `if rotation != 0` diyordu, açı N→0 olunca
        // marker eğri duruyordu.
        //
        // Rotation VERİLMEDİYSE (nil) transform'a DOKUNMA: açı `annotation#rotate`
        // kanalından geliyor olabilir; burada sıfırlamak onu silerdi.
        if let rotation = annotation.rotation {
            annotationView!.transform = rotation == 0
                ? .identity
                : CGAffineTransform(rotationAngle: CGFloat(Double(rotation) * .pi / 180))
        }
        annotationView!.isDraggable = annotation.isDraggable ?? false
        return annotationView!
    }

    func annotationsToAdd(annotations :NSArray) {
        for annotation in annotations {
            let annotationData :Dictionary<String, Any> = annotation as! Dictionary<String, Any>
            addAnnotation(annotationData: annotationData)
        }
    }

    func annotationsToChange(annotations: NSArray) {
        let oldAnnotations :[MKAnnotation] = self.mapView.annotations
        for annotation in annotations {
            let annotationData :Dictionary<String, Any> = annotation as! Dictionary<String, Any>
            for oldAnnotation in oldAnnotations {
                if let oldFlutterAnnotation = oldAnnotation as? FlutterAnnotation {
                    if oldFlutterAnnotation.id == (annotationData["annotationId"] as! String) {
                        let newAnnotation = FlutterAnnotation.init(fromDictionary: annotationData, registrar: registrar)
                        if oldFlutterAnnotation != newAnnotation {
                            if !oldFlutterAnnotation.wasDragged {
                                updateAnnotationOnMap(oldAnnotation: oldFlutterAnnotation, newAnnotation: newAnnotation)
                            } else {
                                oldFlutterAnnotation.wasDragged = false
                            }
                        }
                    }
                }
            }
        }
    }

    func annotationsIdsToRemove(annotationIds: NSArray) {
        for annotationId in annotationIds {
            if let _annotationId :String = annotationId as? String {
                removeAnnotation(id: _annotationId)
            }
        }
    }
    
    func removeAllAnnotations() {
        self.mapView.removeAnnotations(self.mapView.annotations)
    }

    func onAnnotationClick(annotation :MKAnnotation) {
        if let flutterAnnotation :FlutterAnnotation = annotation as? FlutterAnnotation {
            flutterAnnotation.wasDragged = true
            channel.invokeMethod("annotation#onTap", arguments: ["annotationId" : flutterAnnotation.id])
        }
    }
    
    func showAnnotation(with id: String) {
        let annotation = self.getAnnotation(with: id)
        guard annotation != nil else {
            return
        }
        self.mapView.selectAnnotation(annotation!, animated: true)
    }

    func hideAnnotation(with id: String) {
        let annotation = self.getAnnotation(with: id)
        guard annotation != nil else {
            return
        }
        self.mapView.deselectAnnotation(annotation!, animated: true)
    }

    func isAnnotationSelected(with id: String) -> Bool {
        return self.mapView.selectedAnnotations.contains(where: { annotation in return self.getAnnotation(with: id) == (annotation as? FlutterAnnotation)})
    }


    public func removeAnnotation(id: String) {
        if let flutterAnnotation :FlutterAnnotation = self.getAnnotation(with: id) {
            self.mapView.removeAnnotation(flutterAnnotation)
        }
    }

    /// Marker'ı YERİNDE günceller — `removeAnnotation` + `addAnnotation` YAPMAZ.
    ///
    /// Eski hal her Dart-tarafı annotation değişiminde marker'ı silip yeniden
    /// ekliyordu. Qibla'da kullanıcı ok'unun `rotation`/`icon`/`position`'ı
    /// pusula frekansında (~30 örnek/sn) değiştiği için MKMapView marker'ı
    /// saniyede onlarca kez yeniden kuruyor, ekranda "göz kırpma" oluşuyordu.
    /// `FlutterAnnotation.==` bu üç alanı da karşılaştırdığı için Dart tarafında
    /// ne yapılırsa yapılsın buraya düşüyordu; kalıcı çözüm burada.
    ///
    /// `coordinate` `@objc dynamic` olduğu için atama KVO ile MapKit'e bildirilir
    /// (marker kaymaz, zıplamaz). Görsel alanlar mevcut view üzerinde güncellenir.
    private func updateAnnotationOnMap(oldAnnotation: FlutterAnnotation, newAnnotation :FlutterAnnotation) {
        // Icon TÜRÜ değiştiyse view'ın SINIFI da değişmeli (PIN ↔ MARKER ↔ CUSTOM);
        // bu tek meşru sil-ekle yolu. Qibla'da tür sabit (CUSTOM_FROM_BYTES) →
        // bu dal pratikte çalışmaz.
        if oldAnnotation.icon.iconType != newAnnotation.icon.iconType {
            AnnotationUpdateStats.shared.recordRebuild(reason: "iconType")
            removeAnnotation(id: oldAnnotation.id)
            self.mapView.addAnnotation(newAnnotation)
            return
        }

        let iconChanged = oldAnnotation.icon != newAnnotation.icon
        let rotationChanged = oldAnnotation.rotation != newAnnotation.rotation
        let coordinateChanged = oldAnnotation.coordinate.latitude != newAnnotation.coordinate.latitude
            || oldAnnotation.coordinate.longitude != newAnnotation.coordinate.longitude

        // ── Model alanları ────────────────────────────────────────────────
        oldAnnotation.coordinate = newAnnotation.coordinate
        oldAnnotation.title = newAnnotation.title
        oldAnnotation.subtitle = newAnnotation.subtitle
        oldAnnotation.infoWindowConsumesTapEvents = newAnnotation.infoWindowConsumesTapEvents
        oldAnnotation.alpha = newAnnotation.alpha
        oldAnnotation.rotation = newAnnotation.rotation
        oldAnnotation.anchor = newAnnotation.anchor
        oldAnnotation.calloutOffset = newAnnotation.calloutOffset
        oldAnnotation.isVisible = newAnnotation.isVisible
        oldAnnotation.isDraggable = newAnnotation.isDraggable
        oldAnnotation.icon = newAnnotation.icon

        // ── Görsel taraf: mevcut view'ı yeniden kullan ─────────────────────
        guard let view = self.mapView.view(for: oldAnnotation) else {
            // View henüz üretilmemiş (annotation ekranın dışında ya da MapKit
            // daha `viewFor:` çağırmamış). Model güncellendi; view MapKit onu
            // gösterirken `getAnnotationView` üzerinden doğru kurulur.
            AnnotationUpdateStats.shared.recordInPlace(viewMissing: true)
            return
        }

        if iconChanged, newAnnotation.icon.iconType == .CUSTOM_FROM_ASSET
            || newAnnotation.icon.iconType == .CUSTOM_FROM_BYTES {
            // Yalnız görseli değiştir — view'ı atmaya gerek yok. (Qibla'da
            // kıble bulundu/bulunamadı ok ikonunu değiştiriyor.)
            view.image = newAnnotation.icon.image
        }

        // Transform'a YALNIZ rotation fiilen değiştiğinde dokun.
        //
        // `iconChanged`'de dokunmak YANLIŞ olurdu: Qibla açıyı `annotation#rotate`
        // kanalıyla veriyor (annotation'ın `rotation` alanı nil geliyor), ikon
        // değişiminde transform'u sıfırlamak o açıyı silerdi — ok bir anlık düz
        // dururdu. `rotation` nil ise burası hiç çalışmaz, doğru davranış bu.
        if rotationChanged, let degrees = newAnnotation.rotation {
            view.transform = degrees == 0
                ? .identity
                : CGAffineTransform(rotationAngle: CGFloat(Double(degrees) * .pi / 180))
        }

        if !(newAnnotation.isVisible ?? true) {
            view.canShowCallout = false
            view.alpha = 0.0
            view.isDraggable = false
        } else {
            view.canShowCallout = true
            view.alpha = CGFloat(newAnnotation.alpha ?? 1.0)
            view.isDraggable = newAnnotation.isDraggable ?? false
        }

        AnnotationUpdateStats.shared.recordInPlace(
            icon: iconChanged, rotation: rotationChanged, coordinate: coordinateChanged
        )
    }

    private func initInfoWindow(annotation: FlutterAnnotation, annotationView: MKAnnotationView) {
        let x = self.getInfoWindowXOffset(annotationView: annotationView, annotation: annotation)
        let y = self.getInfoWindowYOffset(annotationView: annotationView, annotation: annotation)
        annotationView.calloutOffset = CGPoint(x: x, y: y)
        if #available(iOS 9.0, *) {
            let lines = annotation.subtitle?.split(whereSeparator: { $0.isNewline })
            if lines != nil {
                let customCallout = UIStackView()
                customCallout.axis = .vertical
                customCallout.alignment = .fill
                customCallout.distribution = .fill
                for line in lines! {
                    let subtitle = UILabel()
                    subtitle.text = String(line)
                    customCallout.addArrangedSubview(subtitle)
                }
                annotationView.detailCalloutAccessoryView = customCallout
            }
        }
    }

    func getAnnotation(with id: String) -> FlutterAnnotation? {
        return self.mapView.annotations.filter { annotation in return (annotation as? FlutterAnnotation)?.id == id }.first as? FlutterAnnotation
    }

    public func addAnnotation(annotationData: Dictionary<String, Any>) {
        let annotation :MKAnnotation = FlutterAnnotation(fromDictionary: annotationData, registrar: registrar)
        self.mapView.addAnnotation(annotation)
    }

    private func getPinAnnotationView(annotation: MKAnnotation, id: String) -> MKPinAnnotationView {
        if #available(iOS 11.0, *) {
            self.mapView.register(MKPinAnnotationView.self, forAnnotationViewWithReuseIdentifier: id)
            return self.mapView.dequeueReusableAnnotationView(withIdentifier: id, for: annotation) as! MKPinAnnotationView
        } else {
            return MKPinAnnotationView.init(annotation: annotation, reuseIdentifier: id)
        }
    }

    private func getMarkerAnnotationView(annotation: MKAnnotation, id: String) -> MKAnnotationView {
        if #available(iOS 11.0, *) {
            self.mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: id)
            return self.mapView.dequeueReusableAnnotationView(withIdentifier: id, for: annotation)
        } else {
            return MKPinAnnotationView.init(annotation: annotation, reuseIdentifier: id)
        }
    }

    private func getCustomAnnotationView(annotation: FlutterAnnotation, id: String) -> MKAnnotationView {
        let annotationView: MKAnnotationView?
        if #available(iOS 11.0, *) {
            self.mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: id)
            annotationView = self.mapView.dequeueReusableAnnotationView(withIdentifier: id, for: annotation)
        } else {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: id)
        }
        annotationView?.image = annotation.icon.image
        return annotationView!
    }

    private func getInfoWindowXOffset(annotationView: MKAnnotationView, annotation: FlutterAnnotation) -> CGFloat {
        if annotation.icon.iconType == .PIN {
            return annotationView.frame.origin.x - (annotationView.frame.origin.x * CGFloat(annotation.calloutOffset.x))
        }
        return annotationView.frame.origin.x + (annotationView.frame.width * CGFloat(annotation.calloutOffset.x))
    }

    private func getInfoWindowYOffset(annotationView: MKAnnotationView, annotation: FlutterAnnotation) -> CGFloat {
        return annotationView.frame.height * CGFloat(annotation.calloutOffset.y)
    }
}
