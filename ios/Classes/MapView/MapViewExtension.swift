//
//  MapViewExtension.swift
//  apple_maps_flutter
//
//  Created by Luis Thein on 22.09.19.
//

import Foundation
import UIKit
import MapKit

enum MapViewConstants: Double {
    case MERCATOR_OFFSET = 268435456.0
    case MERCATOR_RADIUS = 85445659.44705395
}

public extension MKMapView {
    // keeps track of the Map values
    private struct Holder {
        static var _zoomLevel: Double = Double(0)
        static var _pitch: CGFloat = CGFloat(0)
        static var _heading: CLLocationDirection = CLLocationDirection(0)
        static var _maxZoomLevel: Double = Double(21)
        static var _minZoomLevel: Double = Double(2)
    }
    
    var maxZoomLevel: Double {
        set(_maxZoomLevel) {
            // Re-applying the SAME limit must not touch the camera. The setter
            // below writes the camera with `animated: false`, which cancels any
            // running `animateCamera`. Hosts re-send options on every rebuild,
            // so without this guard a programmatic zoom animation could be
            // killed dozens of times per second.
            if Holder._maxZoomLevel == _maxZoomLevel { return }
            Holder._maxZoomLevel = _maxZoomLevel
            if Holder._zoomLevel > _maxZoomLevel {
                if #available(iOS 9.0, *) {
                    self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: _maxZoomLevel, animated: false)
                } else {
                    self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: _maxZoomLevel, animated: false)
                }
            }
        }
        get {
            return Holder._maxZoomLevel
        }
    }
    
    var minZoomLevel: Double {
        set(_minZoomLevel) {
            // See `maxZoomLevel`: an unchanged limit must be a no-op, otherwise
            // the camera write below cancels running animations.
            if Holder._minZoomLevel == _minZoomLevel { return }
            Holder._minZoomLevel = _minZoomLevel
            if Holder._zoomLevel < _minZoomLevel {
                if #available(iOS 9.0, *) {
                   self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: _minZoomLevel, animated: false)
                } else {
                   self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: _minZoomLevel, animated: false)
                }
            }
        }
        get {
           return Holder._minZoomLevel
        }
    }
    
    var zoomLevel: Double {
        get {
            return Holder._zoomLevel
        }
    }
    
    var calculatedZoomLevel: Double {
        get {
            let centerPixelSpaceX = self.longitudeToPixelSpaceX(longitude: self.centerCoordinate.longitude)

            let lonLeft = self.centerCoordinate.longitude - (self.region.span.longitudeDelta / 2)

            let leftPixelSpaceX = self.longitudeToPixelSpaceX(longitude: lonLeft)
            let pixelSpaceWidth = abs(centerPixelSpaceX - leftPixelSpaceX) * 2

            let zoomScale = pixelSpaceWidth / Double(self.bounds.size.width)

            let zoomExponent = self.logC(val: zoomScale, forBase: 2)

            var zoomLevel = 21 - zoomExponent
            
            zoomLevel = roundToTwoDecimalPlaces(number: zoomLevel)
            
            Holder._zoomLevel = zoomLevel
            
            return zoomLevel
            
        }
        set (newZoomLevel) {
            Holder._zoomLevel = newZoomLevel
        }
    }
    
    func longitudeToPixelSpaceX(longitude: Double) -> Double {
        return round(MapViewConstants.MERCATOR_OFFSET.rawValue + MapViewConstants.MERCATOR_RADIUS.rawValue * longitude * .pi / 180.0)
    }
    
    func latitudeToPixelSpaceY(latitude: Double) -> Double {
        return round(Double(Float(MapViewConstants.MERCATOR_OFFSET.rawValue) - Float(MapViewConstants.MERCATOR_RADIUS.rawValue) * logf((1 + sinf(Float(latitude * .pi / 180.0))) / (1 - sinf(Float(latitude * .pi / 180.0)))) / Float(2.0)))
    }
    
    func pixelSpaceXToLongitude(pixelX: Double) -> Double {
        return ((round(pixelX) - MapViewConstants.MERCATOR_OFFSET.rawValue) / MapViewConstants.MERCATOR_RADIUS.rawValue) * 180.0 / .pi
    }
    
    func pixelSpaceYToLatitude(pixelY: Double) -> Double {
        return (.pi / 2.0 - 2.0 * atan(exp((round(pixelY) - MapViewConstants.MERCATOR_OFFSET.rawValue) / MapViewConstants.MERCATOR_RADIUS.rawValue))) * 180.0 / .pi
    }
    
    func logC(val: Double, forBase base: Double) -> Double {
        return log(val)/log(base)
    }
    
    func deg2rad(_ number: Double) -> Float {
        return Float(number * .pi / 180)
    }
    
    func roundToTwoDecimalPlaces(number: Double) -> Double {
        let doubleStr = String(format: "%.2f", ceil(number*100)/100)
        return Double(doubleStr)!
    }
    
    func setCenterCoordinate(_ positionData: Dictionary<String, Any>, animated: Bool) {
        let targetList :Array<CLLocationDegrees> = positionData["target"] as? Array<CLLocationDegrees> ?? [self.camera.centerCoordinate.latitude, self.camera.centerCoordinate.longitude]
        let zoom :Double = positionData["zoom"] as? Double ?? Holder._zoomLevel
        Holder._zoomLevel = zoom
        if let pitch :CGFloat = positionData["pitch"] as? CGFloat {
            Holder._pitch = pitch
        }
        if let heading :CLLocationDirection = positionData["heading"] as? CLLocationDirection {
            Holder._heading = heading
        }
        let centerCoordinate :CLLocationCoordinate2D = CLLocationCoordinate2D(latitude:  targetList[0], longitude: targetList[1])
        if #available(iOS 9.0, *) {
            self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: zoom, animated: animated)
        } else {
            self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: zoom, animated: animated)
        }
    }
    
    /// Rotates the camera to `heading` — and optionally recenters it on
    /// `target` — while leaving the camera's SCALE untouched.
    ///
    /// This exists because the `setCenterCoordinate` path cannot express
    /// "rotate only". That path takes a zoom LEVEL and converts it to an
    /// altitude through `getCameraAltitude`, so every rotation has to supply a
    /// zoom value. The two directions are not inverses of each other:
    /// `calculatedZoomLevel` reads the level back from the visible region,
    /// while `getCameraAltitude` derives an altitude from a fixed 15° field of
    /// view. Round-tripping a level through them returns a slightly different
    /// level, so a map that rotates continuously (a qibla compass, say) drifts
    /// away from the zoom the user picked — a little on every frame.
    ///
    /// Here no zoom level is involved at all: the live camera is copied and
    /// only its heading (and center) is modified, so the altitude carries over
    /// unchanged and the scale cannot drift.
    ///
    /// - Returns: `true` when the heading was applied. `false` means the camera
    ///   was not in a usable state and the caller should decide what to do —
    ///   failing silently would leave a rotating map frozen with no way to
    ///   tell why.
    @discardableResult
    func setCameraHeading(heading: CLLocationDirection, target: CLLocationCoordinate2D?, animated: Bool) -> Bool {
        guard heading.isFinite else { return false }

        // A zero-sized map view has no meaningful camera: `layoutSubviews` has
        // not run for these bounds, so altitude and center are still whatever
        // they were beforehand. Writing a camera in that state produces the
        // same broken values the read path has to guard against.
        guard self.bounds.size.width > 0, self.bounds.size.height > 0 else { return false }

        guard let camera = self.camera.copy() as? MKMapCamera else { return false }
        guard camera.altitude.isFinite, camera.altitude > 0 else { return false }

        let wrapped = heading.truncatingRemainder(dividingBy: 360)
        camera.heading = wrapped < 0 ? wrapped + 360 : wrapped

        if let target = target, CLLocationCoordinate2DIsValid(target) {
            camera.centerCoordinate = target
        }

        // Keep `Holder._heading` in sync. `layoutSubviews` and
        // `setCenterCoordinate` both re-apply the camera from the Holder, so a
        // stale value there would snap the map back to the previous heading on
        // the next relayout or programmatic move.
        Holder._heading = camera.heading

        // `Holder._zoomLevel` is deliberately left alone: rotating does not
        // change the scale, so the stored level is still the correct one.
        self.setCamera(camera, animated: animated)
        return true
    }

    func setBounds(_ positionData: Dictionary<String, Any>, animated: Bool) {
        guard let targetList :Array<Array<CLLocationDegrees>> = positionData["target"] as? Array<Array<CLLocationDegrees>> else { return }
        let padding :Double = positionData["padding"] as? Double ?? 0
        let coodinates: Array<CLLocationCoordinate2D> = targetList.map { (coordinate : Array<CLLocationDegrees>) in
            return CLLocationCoordinate2D(latitude:  coordinate[0], longitude: coordinate[1])
        }
        guard let mapRect = coodinates.mapRect() else { return }
        self.setVisibleMapRect(mapRect, edgePadding: UIEdgeInsets(top: CGFloat(padding), left: CGFloat(padding), bottom: CGFloat(padding), right: CGFloat(padding)), animated: animated)
    }
    
    func setCenterCoordinateRegion(centerCoordinate: CLLocationCoordinate2D, zoomLevel: Double, animated: Bool) {
        // clamp large numbers to 28
        let zoomL = min(zoomLevel, 28);
    
        // use the zoom level to compute the region
        let span = self.coordinateSpanWithMapView(centerCoordinate: centerCoordinate, zoomLevel: Int(zoomL))
        let region = MKCoordinateRegion.init(center: centerCoordinate, span: span)
        
        // set the region like normal
        self.setRegion(region, animated: animated)
        
        // Setting the pitch/heading doesn't work while animating yet.
        // The animation will stop if the you change camera properties while it's running.
        if (!animated) {
            self.camera.pitch = Holder._pitch
            self.camera.heading = Holder._heading
        }
    }
    
    func coordinateSpanWithMapView(centerCoordinate: CLLocationCoordinate2D, zoomLevel: Int) -> MKCoordinateSpan  {
        // convert center coordiate to pixel space
        let centerPixelX = self.longitudeToPixelSpaceX(longitude: centerCoordinate.longitude)
        let centerPixelY = self.latitudeToPixelSpaceY(latitude: centerCoordinate.latitude)
    
        // determine the scale value from the zoom level
        let zoomExponent = Double(21 - zoomLevel)
        let zoomScale = pow(2.0, zoomExponent)

        // scale the map’s size in pixel space
        let mapSizeInPixels = self.bounds.size
        let scaledMapWidth = Double(mapSizeInPixels.width) * zoomScale
        let scaledMapHeight = Double(mapSizeInPixels.height) * zoomScale;
    
        // figure out the position of the top-left pixel
        let topLeftPixelX = centerPixelX - (scaledMapWidth / 2);
        let topLeftPixelY = centerPixelY - (scaledMapHeight / 2);
    
        // find delta between left and right longitudes
        let minLng = self.pixelSpaceXToLongitude(pixelX: topLeftPixelX)
        let maxLng = self.pixelSpaceXToLongitude(pixelX: topLeftPixelX + scaledMapWidth)
        let longitudeDelta = maxLng - minLng;
    
        // find delta between top and bottom latitudes
        let minLat = self.pixelSpaceYToLatitude(pixelY: topLeftPixelY)
        let maxLat = self.pixelSpaceYToLatitude(pixelY: topLeftPixelY + scaledMapHeight)
        let latitudeDelta = -1 * (maxLat - minLat)
    
        // create and return the lat/lng span
        return MKCoordinateSpan.init(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    }
    
    @available(iOS 9.0, *)
    func setCenterCoordinateWithAltitude(centerCoordinate: CLLocationCoordinate2D, zoomLevel: Double, animated: Bool) {
        // clamp large numbers to 28
        let zoomL = min(zoomLevel, 28);
        let altitude = getCameraAltitude(centerCoordinate: centerCoordinate, zoomLevel: zoomL)
        self.setCamera(MKMapCamera(lookingAtCenter: centerCoordinate, fromDistance: CLLocationDistance(altitude), pitch: Holder._pitch, heading: Holder._heading), animated: animated)
    }
    
    private func getCameraAltitude(centerCoordinate: CLLocationCoordinate2D, zoomLevel: Double) -> Double {
        // convert center coordiate to pixel space
        let centerPixelY = latitudeToPixelSpaceY(latitude: centerCoordinate.latitude)
        // determine the scale value from the zoom level
        let zoomExponent:Double = 21.0 - zoomLevel
        let zoomScale:Double = pow(2.0, zoomExponent)
        // scale the map’s size in pixel space
        let mapSizeInPixels = self.bounds.size
        let scaledMapHeight = Double(mapSizeInPixels.height) * zoomScale
        // figure out the position of the top-left pixel
        let topLeftPixelY = centerPixelY - (scaledMapHeight / 2.0)
        // find delta between left and right longitudes
        let maxLat = pixelSpaceYToLatitude(pixelY: topLeftPixelY + scaledMapHeight)
        let topBottom = CLLocationCoordinate2D.init(latitude: maxLat, longitude: centerCoordinate.longitude)
        
        let distance = MKMapPoint.init(centerCoordinate).distance(to: MKMapPoint.init(topBottom))
        let altitude = distance / tan(.pi*(15/180.0))
        
        return altitude
    }
    
    /// The zoom level the camera is ACTUALLY at, derived from `camera.altitude`.
    ///
    /// Why not `calculatedZoomLevel`: that reads the level back from
    /// `region.span.longitudeDelta`, and the visible region is the BOUNDING BOX
    /// of a rotated viewport — so on a rotating map the same camera reads up to
    /// a full zoom level differently (measured: 6.01 … 7.02 with the camera
    /// untouched on a 390x844 screen). It cannot be used for a decision.
    ///
    /// `camera.altitude` is heading-independent. This inverts the exact function
    /// the write path uses (`getCameraAltitude`) by bisection, so a commanded
    /// level and the level reported here are on the same scale by construction —
    /// no formula drift between read and write.
    ///
    /// Returns `nil` when the view has no usable bounds/camera yet.
    func actualZoomLevel() -> Double? {
        guard self.bounds.size.width > 0, self.bounds.size.height > 0 else { return nil }
        let altitude = self.camera.altitude
        guard altitude.isFinite, altitude > 0 else { return nil }
        let center = self.centerCoordinate
        guard CLLocationCoordinate2DIsValid(center) else { return nil }

        // `getCameraAltitude` is monotonically DECREASING in zoom (higher zoom =
        // closer camera), so bisection needs the comparison in that direction.
        var lo = 1.0    // far
        var hi = 21.0   // near
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let midAlt = getCameraAltitude(centerCoordinate: center, zoomLevel: mid)
            guard midAlt.isFinite, midAlt > 0 else { return nil }
            if midAlt > altitude {
                lo = mid    // still too far out
            } else {
                hi = mid
            }
        }
        return (lo + hi) / 2
    }

    func getVisibleRegion() -> Dictionary<String, Array<Double>> {
        if self.bounds.size != CGSize.zero {
            // convert center coordiate to pixel space
            let centerPixelX = self.longitudeToPixelSpaceX(longitude: self.centerCoordinate.longitude)
            let centerPixelY = self.latitudeToPixelSpaceY(latitude: self.centerCoordinate.latitude)

            // determine the scale value from the zoom level
            let zoomExponent = Double(21 - Holder._zoomLevel)
            let zoomScale = pow(2.0, zoomExponent)

            // scale the map’s size in pixel space
            let mapSizeInPixels = self.bounds.size
            let scaledMapWidth = Double(mapSizeInPixels.width) * zoomScale
            let scaledMapHeight = Double(mapSizeInPixels.height) * zoomScale;

            // figure out the position of the top-left pixel
            let topLeftPixelX = centerPixelX - (scaledMapWidth / 2);
            let topLeftPixelY = centerPixelY - (scaledMapHeight / 2);

            // find the southwest coordinate
            let minLng = self.pixelSpaceXToLongitude(pixelX: topLeftPixelX)
            let minLat = self.pixelSpaceYToLatitude(pixelY: topLeftPixelY)

            // find the northeast coordinate
            let maxLng = self.pixelSpaceXToLongitude(pixelX: topLeftPixelX + scaledMapWidth)
            let maxLat = self.pixelSpaceYToLatitude(pixelY: topLeftPixelY + scaledMapHeight)

            return ["northeast": [minLat, maxLng], "southwest": [maxLat, minLng]]
        }
        return ["northeast": [0.0, 0.0], "southwest": [0.0, 0.0]]
    }
    
    func zoomIn(animated: Bool) {
        if Holder._zoomLevel - 1 <= Holder._maxZoomLevel {
            if Holder._zoomLevel < 2 {
                Holder._zoomLevel = 2
            }
            Holder._zoomLevel += 1
            if #available(iOS 9.0, *) {
                self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
            } else {
                self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
            }
        }
    }
    
    func zoomOut(animated: Bool) {
        if Holder._zoomLevel - 1 >= Holder._minZoomLevel {
            Holder._zoomLevel -= 1
            if round(Holder._zoomLevel) <= 2 {
               Holder._zoomLevel = 0
            }

            if #available(iOS 9.0, *) {
               self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
            } else {
               self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
            }
        }
    }
    
    func zoomTo(newZoomLevel: Double, animated: Bool) {
        if newZoomLevel < Holder._minZoomLevel {
            Holder._zoomLevel = Holder._minZoomLevel
        } else if newZoomLevel > Holder._maxZoomLevel {
            Holder._zoomLevel = Holder._maxZoomLevel
        } else {
            Holder._zoomLevel = newZoomLevel
        }

        if #available(iOS 9.0, *) {
            self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
        } else {
            self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
        }
    }
    
    func zoomBy(zoomBy: Double, animated: Bool) {
        if Holder._zoomLevel + zoomBy < Holder._minZoomLevel {
            Holder._zoomLevel = Holder._minZoomLevel
        } else if Holder._zoomLevel + zoomBy > Holder._maxZoomLevel {
            Holder._zoomLevel = Holder._maxZoomLevel
        } else {
            Holder._zoomLevel = Holder._zoomLevel + zoomBy
        }
        
        if #available(iOS 9.0, *) {
            self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
        } else {
            self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
        }
    }
    
    func updateStoredCameraValues(newZoomLevel: Double, newPitch: CGFloat, newHeading: CLLocationDirection) {
        Holder._zoomLevel = newZoomLevel
        Holder._pitch = newPitch
        Holder._heading = newHeading
    }
}

extension Array where Element == CLLocationCoordinate2D {
    func mapRect() -> MKMapRect? {
        return map(MKMapPoint.init).mapRect()
    }
}

extension Array where Element == CLLocation {
    func mapRect() -> MKMapRect? {
        return map { MKMapPoint($0.coordinate) }.mapRect()
    }
}

extension Array where Element == MKMapPoint {
    func mapRect() -> MKMapRect? {
        guard count > 0 else { return nil }

        let xs = map { $0.x }
        let ys = map { $0.y }

        let west = xs.min()!
        let east = xs.max()!
        let width = east - west

        let south = ys.min()!
        let north = ys.max()!
        let height = north - south

        return MKMapRect(x: west, y: south, width: width, height: height)
    }
}
