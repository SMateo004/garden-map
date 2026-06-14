import 'dart:async';
import 'package:geolocator/geolocator.dart';

Stream<Map<String, double>> watchGpsPosition() async* {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;
  }
  if (permission == LocationPermission.deniedForever) return;

  const settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5, // meters — only emit when moved 5m to save battery
  );

  yield* Geolocator.getPositionStream(locationSettings: settings).map(
    (pos) => {
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy': pos.accuracy,
    },
  );
}

Future<Map<String, double>?> getCurrentGpsPosition() async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return {'lat': pos.latitude, 'lng': pos.longitude, 'accuracy': pos.accuracy};
  } catch (_) {
    return null;
  }
}
