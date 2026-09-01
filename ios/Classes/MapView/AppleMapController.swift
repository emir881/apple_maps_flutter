import Foundation
import MapKit

public class AppleMapController: NSObject, FlutterPlatformView {
    var mapView: FlutterMapView
    var registrar: FlutterPluginRegistrar
    var channel: FlutterMethodChannel
    var initialCameraPosition: [String: Any]
    var onCalloutTapGestureRecognizer: UITapGestureRecognizer?
    var options: [String: Any]
    var currentlySelectedAnnotation: String?
    var snapShotOptions: MKMapSnapshotter.Options = MKMapSnapshotter.Options()
    var snapShot: MKMapSnapshotter?
    
    let availableCaps: Dictionary<String, CGLineCap> = [
        "buttCap": CGLineCap.butt,
        "roundCap": CGLineCap.round,
        "squareCap": CGLineCap.square
    ]
    
    let availableJointTypes: Array<CGLineJoin> = [
        CGLineJoin.miter,
        CGLineJoin.bevel,
        CGLineJoin.round
    ]
    
    public init(withFrame frame: CGRect, withRegistrar registrar: FlutterPluginRegistrar, withargs args: Dictionary<String, Any> ,withId id: Int64) {
        self.options = args["options"] as! [String: Any]
        self.channel = FlutterMethodChannel(name: "apple_maps_plugin.luisthein.de/apple_maps_\(id)", binaryMessenger: registrar.messenger())
        
        self.mapView = FlutterMapView(channel: channel, options: options)
        if #available(iOS 13.0, *) {
            self.mapView.overrideUserInterfaceStyle = .light
         }
        self.registrar = registrar
        
        self.initialCameraPosition = args["initialCameraPosition"]! as! Dictionary<String, Any>
        
        super.init()
        
        self.mapView.delegate = self
        self.mapView.setCenterCoordinate(initialCameraPosition, animated: false)
        self.setMethodCallHandlers()

        if let annotationsToAdd: NSArray = args["annotationsToAdd"] as? NSArray {
            self.annotationsToAdd(annotations: annotationsToAdd)
        }
        if let polylinesToAdd: NSArray = args["polylinesToAdd"] as? NSArray {
            self.addPolylines(polylineData: polylinesToAdd)
        }
        if let polygonsToAdd: NSArray = args["polygonsToAdd"] as? NSArray {
            self.addPolygons(polygonData: polygonsToAdd)
        }
        if let circlesToAdd: NSArray = args["circlesToAdd"] as? NSArray {
            self.addCircles(circleData: circlesToAdd)
        }
        self.onCalloutTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.calloutTapped(_:)))

    }
    
    deinit {
        // Detach the method-call handler so any in-flight messages from Dart
        // can't reach a deallocated `self` (was crashing as EXC_BAD_ACCESS in
        // setMethodCallHandler / annotationsToChange / objc_msgSend).
        channel.setMethodCallHandler(nil)
        self.removeAllAnnotations()
        self.removeAllCircles()
        self.removeAllPolygons()
        self.removeAllPolylines()
    }

    public func view() -> UIView {
        return mapView
    }
    
    /// Kameranin hem DONEBILDIGI hem de ISTENEN UZAKLIKTA KALDIGI en uzak
    /// (en kucuk) zoom seviyesini olcer.
    ///
    /// MapKit'in uzak olcekte IKI ayri davranisi var, ikisi de olculdu:
    ///  1. Cok uzak (zoom=1 / altitude ~31.283.000 m): `setCamera(heading:)` kabul
    ///     edilir ama UYGULANMAZ -> camera.heading = 0, altitude korunur.
    ///  2. Ara bolge: heading UYGULANIR ama MapKit kamerayi kendisi ICERI CEKER
    ///     -> altitude istenenden kucuk doner.
    ///
    /// Yalniz heading'e bakan bir olcum 2. durumu "burasi donuyor" sayar ve fazla
    /// uzak bir hedef secer; zoom-out oraya gider (heading=0 oldugu icin kamera
    /// kalir), ilk pusula donusunde MapKit kamerayi iceri ceker ve kullanici
    /// "once daha uzaga gitti, sonra geri geldi" diye gorur. Bu yuzden kriter ciftli:
    /// **heading tutacak VE altitude korunacak.**
    ///
    /// Esik ekran YUKSEKLIGINE bagli (altitude hesabi bounds.height kullanir), yani
    /// cihazdan cihaza kayar; sabit gomulemez, calisma aninda olculur.
    ///
    /// Yontem: [from, 14] araliginda ikili arama (~6 deneme). Denemeler animasyonsuz
    /// ve ayni runloop turunda; sonunda ORIJINAL kamera geri konur -> ekranda ara
    /// durum cizilmez.
    ///
    /// Doner: ["zoom": bulunan seviye (hicbiri tutmuyorsa -1), "headOk"/"altOk":
    /// bulunan seviyenin bayraklari, "belowHead"/"belowAlt": bir alt (daha uzak)
    /// seviyede hangi kriterin dustugu — teshis icin.
    private func maxRotatableZoom(from minZoom: Double) -> [String: Any] {
        // Harita henuz yerlesmemisse (bounds sifir) altitude hesabi 0 uretir ve olcum
        // anlamsiz olur; -1 donup Dart'in guvenli fallback'ine birak.
        guard mapView.bounds.size.height > 0, mapView.bounds.size.width > 0 else {
            return ["zoom": -1.0, "headOk": false, "altOk": false,
                    "belowHead": false, "belowAlt": false, "reason": "zeroBounds"]
        }
        // `as!` yerine guard: copy() teorik olarak beklenen tipi dondurmezse cokmek yerine
        // olcumden temiz cikilir (kamera hic degistirilmemis olur).
        guard let original = mapView.camera.copy() as? MKMapCamera else {
            return ["zoom": -1.0, "headOk": false, "altOk": false,
                    "belowHead": false, "belowAlt": false, "reason": "cameraCopyFailed"]
        }
        let center = mapView.centerCoordinate
        let testHeading: CLLocationDirection = 90
        let altTolerance = 0.03   // %3: MapKit yuvarlamasini gecer, gercek clamp'i yakalar

        // Olcum sirasinda 8-14 kez setCamera yapiliyor; her biri `regionDidChangeAnimated`
        // tetikleyip Dart'a `camera#onIdle` gonderir ve gereksiz rebuild firtinasi yaratirdi.
        // Delegate'i olcum boyunca askiya al, sonunda geri tak (defer ile her yolda).
        let savedDelegate = mapView.delegate
        mapView.delegate = nil
        defer { mapView.delegate = savedDelegate }

        // Bir seviyeyi dene: (heading uygulandi mi, kamera istenen uzaklikta kaldi mi)
        func probe(_ zoom: Double) -> (head: Bool, alt: Bool) {
            let wantAlt = probeAltitude(centerCoordinate: center, zoomLevel: zoom)
            mapView.setCamera(
                MKMapCamera(lookingAtCenter: center, fromDistance: wantAlt, pitch: 0, heading: testHeading),
                animated: false)
            let headOk = abs(mapView.camera.heading - testHeading) < 1.0
            let gotAlt = mapView.camera.altitude
            let altOk = wantAlt > 0 && abs(gotAlt - wantAlt) / wantAlt < altTolerance
            return (headOk, altOk)
        }

        func holds(_ zoom: Double) -> Bool {
            let r = probe(zoom)
            return r.head && r.alt
        }

        var lo = minZoom      // beklenen: TUTMUYOR
        var hi = 14.0         // beklenen: TUTUYOR
        var found = hi

        if holds(lo) {                    // istenen zoom zaten hem donuyor hem kaliyor
            found = lo
        } else if !holds(hi) {            // beklenmedik: hicbir yerde tutmuyor
            let r = probe(hi)
            let b = probe(hi - 0.25)
            mapView.setCamera(original, animated: false)
            return ["zoom": -1.0, "headOk": r.head, "altOk": r.alt,
                    "belowHead": b.head, "belowAlt": b.alt]
        } else {
            while hi - lo > 0.25 {
                let mid = (lo + hi) / 2
                if holds(mid) { hi = mid } else { lo = mid }
            }
            found = hi
        }

        let r = probe(found)
        let b = probe(found - 0.25)       // bir alt seviyede hangi kriter dusuyor?
        mapView.setCamera(original, animated: false)
        return ["zoom": found, "headOk": r.head, "altOk": r.alt,
                "belowHead": b.head, "belowAlt": b.alt]
    }

    /// MapViewExtension'daki `getCameraAltitude` private oldugu icin ayni formul.
    private func probeAltitude(centerCoordinate: CLLocationCoordinate2D, zoomLevel: Double) -> Double {
        let centerPixelY = self.mapView.latitudeToPixelSpaceY(latitude: centerCoordinate.latitude)
        let zoomScale = pow(2.0, 21.0 - zoomLevel)
        let scaledMapHeight = Double(self.mapView.bounds.size.height) * zoomScale
        let topLeftPixelY = centerPixelY - (scaledMapHeight / 2.0)
        let maxLat = self.mapView.pixelSpaceYToLatitude(pixelY: topLeftPixelY + scaledMapHeight)
        let topBottom = CLLocationCoordinate2D(latitude: maxLat, longitude: centerCoordinate.longitude)
        let distance = MKMapPoint(centerCoordinate).distance(to: MKMapPoint(topBottom))
        return distance / tan(.pi * (15 / 180.0))
    }
    
    @objc func calloutTapped(_ sender: UITapGestureRecognizer? = nil) {
        if self.currentlySelectedAnnotation != nil {
            self.channel.invokeMethod("infoWindow#onTap", arguments: ["annotationId": self.currentlySelectedAnnotation!])
        }
    }
    
    private func setMethodCallHandlers() {
        channel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            // `unowned self` crashed with EXC_BAD_ACCESS when Dart dispatched a
            // method call (annotations#update, etc.) after the controller had
            // already been disposed. `weak self` lets us bail out cleanly.
            guard let self = self else {
                result(FlutterError(
                    code: "CONTROLLER_RELEASED",
                    message: "AppleMapController was deallocated before handling \(call.method)",
                    details: nil
                ))
                return
            }
            if let args: Dictionary<String, Any> = call.arguments as? Dictionary<String,Any> {
                switch(call.method) {
                case "annotations#update":
                    self.annotationUpdate(args: args)
                    result(nil)
                    break
                case "annotations#hideInfoWindow":
                    self.hideAnnotation(with: args["annotationId"] as! String)
                    break
                case "annotations#isInfoWindowShown":
                    result(self.isAnnotationSelected(with: args["annotationId"] as! String))
                    break
                case "polylines#update":
                    self.polylineUpdate(args: args)
                    result(nil)
                    break
                case "polygons#update":
                    self.polygonUpdate(args: args)
                    result(nil)
                    break
                case "circles#update":
                    self.circleUpdate(args: args)
                    result(nil)
                    break
                case "map#update":
                    self.mapView.interpretOptions(options: args["options"] as! Dictionary<String, Any>)
                    break
                case "camera#animate":
                    self.animateCamera(args: args)
                    result(nil)
                    break
                case "camera#move":
                    self.moveCamera(args: args)
                    result(nil)
                    break
                case "annotation#rotate":
                    self.rotateAnnotation(args:args)
                    result(nil)
                    break
                case "camera#convert":
                    self.cameraConvert(args: args, result: result)
                    break
                case "qibla#maxRotatableZoom":
                    result(self.maxRotatableZoom(from: args["fromZoom"] as? Double ?? 1.0))
                    break
                case "map#takeSnapshot":
                    self.takeSnapshot(options: SnapshotOptions.init(options: args), onCompletion: { (snapshot: FlutterStandardTypedData?, error: Error?) -> Void in
                        // Swift `Error` is not encodable by FlutterStandardCodec; wrap it as FlutterError.
                        // Previously `result(snapshot ?? error)` would crash with
                        // NSInternalInconsistencyException: "Unsupported value for standard codec".
                        if let snapshot = snapshot {
                            result(snapshot)
                        } else if let error = error {
                            result(FlutterError(
                                code: "MAP_SNAPSHOT_FAILED",
                                message: error.localizedDescription,
                                details: nil
                            ))
                        } else {
                            result(FlutterError(
                                code: "MAP_SNAPSHOT_EMPTY",
                                message: "Snapshot returned empty result",
                                details: nil
                            ))
                        }
                    })
                default:
                    result(FlutterMethodNotImplemented)
                    break
                }
            } else {
                switch call.method {
                case "map#getVisibleRegion":
                    result(self.mapView.getVisibleRegion())
                    break
                case "map#isCompassEnabled":
                    if #available(iOS 9.0, *) {
                        result(self.mapView.showsCompass)
                    } else {
                        result(false)
                    }
                    break
                case "map#isPitchGesturesEnabled":
                    result(self.mapView.isPitchEnabled)
                    break
                case "map#isScrollGesturesEnabled":
                    result(self.mapView.isScrollEnabled)
                    break
                case "map#isZoomGesturesEnabled":
                    result(self.mapView.isZoomEnabled)
                    break
                case "map#isRotateGesturesEnabled":
                    result(self.mapView.isRotateEnabled)
                    break
                case "map#isMyLocationButtonEnabled":
                    result(self.mapView.isMyLocationButtonShowing ?? false)
                    break
                case "map#getMinMaxZoomLevels":
                    result([self.mapView.minZoomLevel, self.mapView.maxZoomLevel])
                    break
                case "camera#getZoomLevel":
                    result(self.mapView.calculatedZoomLevel)
                    break
                default:
                    result(FlutterMethodNotImplemented)
                    break
                }
            }
        })
    }
    
    private func annotationUpdate(args: Dictionary<String, Any>) -> Void {
        if let annotationsToAdd = args["annotationsToAdd"] as? NSArray {
            if annotationsToAdd.count > 0 {
                self.annotationsToAdd(annotations: annotationsToAdd)
            }
        }
        if let annotationsToChange = args["annotationsToChange"] as? NSArray {
            if annotationsToChange.count > 0 {
                self.annotationsToChange(annotations: annotationsToChange)
            }
        }
        if let annotationsToDelete = args["annotationIdsToRemove"] as? NSArray {
            if annotationsToDelete.count > 0 {
                self.annotationsIdsToRemove(annotationIds: annotationsToDelete)
            }
        }
    }
    
    private func polygonUpdate(args: Dictionary<String, Any>) -> Void {
        if let polyligonsToAdd: NSArray = args["polygonsToAdd"] as? NSArray {
            self.addPolygons(polygonData: polyligonsToAdd)
        }
        if let polygonsToChange: NSArray = args["polygonsToChange"] as? NSArray {
            self.changePolygons(polygonData: polygonsToChange)
        }
        if let polygonsToRemove: NSArray = args["polygonIdsToRemove"] as? NSArray {
            self.removePolygons(polygonIds: polygonsToRemove)
        }
    }
    
    private func polylineUpdate(args: Dictionary<String, Any>) -> Void {
        if let polylinesToAdd: NSArray = args["polylinesToAdd"] as? NSArray {
            self.addPolylines(polylineData: polylinesToAdd)
        }
        if let polylinesToChange: NSArray = args["polylinesToChange"] as? NSArray {
            self.changePolylines(polylineData: polylinesToChange)
        }
        if let polylinesToRemove: NSArray = args["polylineIdsToRemove"] as? NSArray {
            self.removePolylines(polylineIds: polylinesToRemove)
        }
    }
    
    private func circleUpdate(args: Dictionary<String, Any>) -> Void {
        if let circlesToAdd: NSArray = args["circlesToAdd"] as? NSArray {
            self.addCircles(circleData: circlesToAdd)
        }
        if let circlesToChange: NSArray = args["circlesToChange"] as? NSArray {
            self.changeCircles(circleData: circlesToChange)
        }
        if let circlesToRemove: NSArray = args["circleIdsToRemove"] as? NSArray {
            self.removeCircles(circleIds: circlesToRemove)
        }
    }
    
    private func moveCamera(args: Dictionary<String, Any>) -> Void {
        let positionData: Dictionary<String, Any> = self.toPositionData(data: args["cameraUpdate"] as! Array<Any>, animated: false)
        if !positionData.isEmpty {
            guard let _ = positionData["moveToBounds"] else {
                self.mapView.setCenterCoordinate(positionData, animated: false)
                return
            }
            self.mapView.setBounds(positionData, animated: false)
        }
    }

     private func rotateAnnotation(args: Dictionary<String, Any>) -> Void {
        
        guard let annotationData = args["annotation"] as? Dictionary<String, Any> else {
        print("rotation: annotation is null")
           return;
        }
         guard let id = annotationData["id"] as? String else {
             print("rotation: annotation is null")
             return;
         }
         guard let rotation = annotationData["rotation"] as? CGFloat else {
             print("rotation: rotation is null")
             return;
         }
         var duration:Double? = 0.5;
         if(annotationData["duration"] != nil){
             duration = annotationData["duration"] as? Double
         }
         guard let annotation = self.mapView.annotations.filter({ annotation in return (annotation as? FlutterAnnotation)?.id == annotationData["id"] as? String}).first as? FlutterAnnotation else {
             print("rotation: There is no annotation with this id")
             return
         }
         UIView.animate(withDuration: duration ?? 0.5) {
             self.mapView.view(for: annotation)?.transform = CGAffineTransform(rotationAngle: self.degreesToRadians(degrees: rotation))
         }
        
    }
    func degreesToRadians(degrees: Double) -> CGFloat { return CGFloat(degrees * .pi / 180.0) }

    private func animateCamera(args: Dictionary<String, Any>) -> Void {
        let positionData: Dictionary<String, Any> = self.toPositionData(data: args["cameraUpdate"] as! Array<Any>, animated: true)
        if !positionData.isEmpty {
            guard let _ = positionData["moveToBounds"] else {
                self.mapView.setCenterCoordinate(positionData, animated: true)
                return
            }
            self.mapView.setBounds(positionData, animated: true)
        }
    }
    
    private func cameraConvert(args: Dictionary<String, Any>, result: FlutterResult) -> Void {
        guard let annotation = args["annotation"] as? Array<Double> else {
            result(nil)
            return
        }
        let point = self.mapView.convert(CLLocationCoordinate2D(latitude: annotation[0] , longitude: annotation[1]), toPointTo: self.view())
        result(["point": [point.x, point.y]])
    }
    
    private func toPositionData(data: Array<Any>, animated: Bool) -> Dictionary<String, Any> {
        var positionData: Dictionary<String, Any> = [:]
        if let update: String = data[0] as? String {
            switch(update) {
            case "newCameraPosition":
                if let _positionData : Dictionary<String, Any> = data[1] as? Dictionary<String, Any> {
                    positionData = _positionData
                }
            case "newLatLng":
                if let _positionData : Array<Any> = data[1] as? Array<Any> {
                    positionData = ["target": _positionData]
                }
            case "newLatLngZoom":
                if let _positionData: Array<Any> = data[1] as? Array<Any> {
                    let zoom: Double = data[2] as? Double ?? 0
                    positionData = ["target": _positionData, "zoom": zoom]
                }
            case "newLatLngBounds":
                if let _positionData: Array<Any> = data[1] as? Array<Any> {
                    let padding: Double = data[2] as? Double ?? 0
                    positionData = ["target": _positionData, "padding": padding, "moveToBounds": false]
                }
            case "zoomBy":
                if let zoomBy: Double = data[1] as? Double {
                    mapView.zoomBy(zoomBy: zoomBy, animated: animated)
                }
            case "zoomTo":
                if let zoomTo: Double = data[1] as? Double {
                    mapView.zoomTo(newZoomLevel: zoomTo, animated: animated)
                }
            case "zoomIn":
                mapView.zoomIn(animated: animated)
            case "zoomOut":
                mapView.zoomOut(animated: animated)
            default:
                positionData = [:]
            }
            return positionData
        }
        return [:]
    }
}


extension AppleMapController: MKMapViewDelegate {
    // onIdle
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        self.channel.invokeMethod("camera#onIdle", arguments: "")
    }
    
    // onMoveStarted
    public func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        self.channel.invokeMethod("camera#onMoveStarted", arguments: "")
    }
    
    
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        } else if let flutterAnnotation = annotation as? FlutterAnnotation {
            return self.getAnnotationView(annotation: flutterAnnotation)
        }
        return nil
    }

    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)  {
        if let annotation :FlutterAnnotation = view.annotation as? FlutterAnnotation  {
            if annotation.infoWindowConsumesTapEvents {
                view.addGestureRecognizer(self.onCalloutTapGestureRecognizer!)
            }
            self.currentlySelectedAnnotation = annotation.id
            self.onAnnotationClick(annotation: annotation)
        }
    }
    
    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is FlutterPolyline {
            return self.polylineRenderer(overlay: overlay)
        } else if overlay is FlutterPolygon {
            return self.polygonRenderer(overlay: overlay)
        } else if overlay is FlutterCircle {
            return self.circleRenderer(overlay: overlay)
        }
        return MKOverlayRenderer()
    }
}

extension AppleMapController {
    private func takeSnapshot(options: SnapshotOptions, onCompletion: @escaping (FlutterStandardTypedData?, Error?) -> Void) {
        // MKMapSnapshotOptions.setSize throws NSInvalidArgumentException ("Cannot
        // set a zero area size") if the map view has not been laid out yet (zero
        // frame), e.g. a snapshot requested before first layout / while hidden.
        let mapSize = self.mapView.frame.size
        guard mapSize.width > 0, mapSize.height > 0 else {
            onCompletion(nil, NSError(
                domain: "AppleMapController",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Map has zero size; snapshot skipped"]
            ))
            return
        }

        // MKMapSnapShotOptions setting.
        snapShotOptions.region = self.mapView.region
        snapShotOptions.size = mapSize
        snapShotOptions.scale = UIScreen.main.scale
        snapShotOptions.showsBuildings = options.showBuildings
        snapShotOptions.showsPointsOfInterest = options.showPointsOfInterest
        snapShotOptions.mapType = MKMapType.satellite

        
        // Set MKMapSnapShotOptions to MKMapSnapShotter.
        snapShot = MKMapSnapshotter(options: snapShotOptions)
        
        snapShot?.cancel()
        
        if #available(iOS 10.0, *) {
            snapShot?.start { [weak self] snapshot, error in
                // Use `weak` instead of `unowned` so that disposing the controller
                // mid-snapshot does not crash with EXC_BAD_ACCESS.
                guard let self = self else {
                    onCompletion(nil, NSError(
                        domain: "AppleMapController",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Controller deallocated during snapshot"]
                    ))
                    return
                }
                guard let snapshot = snapshot, error == nil else {
                    onCompletion(nil, error ?? NSError(
                        domain: "AppleMapController",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown snapshot error"]
                    ))
                    return
                }

                let image = UIGraphicsImageRenderer(size: self.snapShotOptions.size).image { context in
                    snapshot.image.draw(at: .zero)
                    let rect = self.snapShotOptions.mapRect
                    for overlay in self.mapView.overlays {
                        if ((overlay.intersects?(rect)) != nil) {
                            self.drawOverlays(overlay: overlay, snapshot: snapshot, context: context)
                        }
                    }
                    for annotation in self.mapView.getMapViewAnnotations() {
                        self.drawAnnotations(annotation: annotation, point: snapshot.point(for: annotation!.coordinate))
                    }

                }

                if let imageData = image.pngData() {
                    onCompletion(FlutterStandardTypedData.init(bytes: imageData), nil)
                } else {
                    // Previously this path silently dropped the callback, leaving
                    // the Dart-side Future hanging forever.
                    onCompletion(nil, NSError(
                        domain: "AppleMapController",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to encode snapshot as PNG"]
                    ))
                }
            }
        } else {
            onCompletion(nil, NSError(
                domain: "AppleMapController",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "iOS 10+ required for snapshot"]
            ))
        }
    }
    
    private func drawAnnotations(annotation: FlutterAnnotation?, point: CGPoint) {
        guard annotation != nil else {
            return
        }
        let annotationView = self.getAnnotationView(annotation: annotation!)
        
        var offsetPoint = point
        
        offsetPoint.x -= annotationView.bounds.width / 2
        offsetPoint.y -= annotationView.bounds.height / 2
        
        
        if #available(iOS 11.0, *), annotationView is MKMarkerAnnotationView {
            annotationView.drawHierarchy(in: CGRect(x: offsetPoint.x, y: offsetPoint.y, width: annotationView.bounds.width, height: annotationView.bounds.height), afterScreenUpdates: true)
        } else {
            offsetPoint.x += annotationView.centerOffset.x
            offsetPoint.y += annotationView.centerOffset.y
            let annotationImage = annotationView.image
            annotationImage?.draw(at: offsetPoint)
        }
    }

    @available(iOS 10.0, *)
    private func drawOverlays(overlay: MKOverlay?, snapshot: MKMapSnapshotter.Snapshot, context: UIGraphicsRendererContext) {
        guard overlay != nil else {
            return
        }
        
        if let flutterOverlay: FlutterOverlay = overlay as? FlutterOverlay {
            flutterOverlay.getCAShapeLayer(snapshot: snapshot).render(in: context.cgContext)
        }
        
    }
}
