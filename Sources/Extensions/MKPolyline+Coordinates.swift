import MapKit

extension MKPolyline {
    var coordinatePoints: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: Int(pointCount))
        getCoordinates(&coords, range: NSRange(location: 0, length: Int(pointCount)))
        return coords
    }
}
