import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Constantes geográficas de zonas de Santa Cruz de la Sierra.
/// Usadas en el marketplace, selector de dirección y cualquier componente
/// que necesite mostrar o filtrar por zona.

const LatLng kSantaCruzCenter = LatLng(-17.775, -63.175);
const double kZoneMapDefaultZoom = 12.5;

const Map<String, String> kZoneLabels = {
  'EQUIPETROL': 'Equipetrol',
  'URBARI': 'Urbari',
  'NORTE': 'El Norte',
  'LAS_PALMAS': 'Las Palmas',
  'CENTRO': 'Centro Primer Anillo',
  'REMANZO': 'Remanzo y Sevillas',
  'SUR': 'El Sur',
  'URUBO_NORTE': 'Urubo Norte',
  'URUBO_SUR': 'Urubo Sur',
};

const Map<String, Color> kZoneColors = {
  'EQUIPETROL': Color(0xFF4CAF50),
  'URBARI': Color(0xFF2196F3),
  'NORTE': Color(0xFF00BCD4),
  'LAS_PALMAS': Color(0xFFFF9800),
  'CENTRO': Color(0xFFE91E63),
  'REMANZO': Color(0xFF3F51B5),
  'SUR': Color(0xFF9C27B0),
  'URUBO_NORTE': Color(0xFF00897B),
  'URUBO_SUR': Color(0xFF6D4C41),
};

const Map<String, LatLng> kZoneCenters = {
  'EQUIPETROL': LatLng(-17.7641, -63.1958),
  'URBARI': LatLng(-17.7965, -63.1979),
  'NORTE': LatLng(-17.7630, -63.1763),
  'LAS_PALMAS': LatLng(-17.8031, -63.2074),
  'CENTRO': LatLng(-17.7911, -63.1782),
  'REMANZO': LatLng(-17.6943, -63.1576),
  'SUR': LatLng(-17.832, -63.179),
  'URUBO_NORTE': LatLng(-17.7448, -63.2251),
  'URUBO_SUR': LatLng(-17.7752, -63.2367),
};

const Map<String, double> kZoneZooms = {
  'EQUIPETROL': 14.5,
  'URBARI': 14.5,
  'NORTE': 14.5,
  'LAS_PALMAS': 14.5,
  'CENTRO': 14.0,
  'REMANZO': 14.5,
  'SUR': 14.0,
  'URUBO_NORTE': 13.5,
  'URUBO_SUR': 13.5,
};

const Map<String, List<LatLng>> kZonePolygons = {
  'EQUIPETROL': [
    LatLng(-17.765799, -63.205165),
    LatLng(-17.756941, -63.200993),
    LatLng(-17.752727, -63.191903),
    LatLng(-17.771688, -63.188895),
    LatLng(-17.773695, -63.191993),
  ],
  'CENTRO': [
    LatLng(-17.784393, -63.188845),
    LatLng(-17.782869, -63.172125),
    LatLng(-17.791076, -63.172763),
    LatLng(-17.797915, -63.175423),
    LatLng(-17.799130, -63.181808),
  ],
  'URBARI': [
    LatLng(-17.790265, -63.194629),
    LatLng(-17.798016, -63.193299),
    LatLng(-17.803385, -63.199577),
    LatLng(-17.794369, -63.203887),
  ],
  'LAS_PALMAS': [
    LatLng(-17.798168, -63.204758),
    LatLng(-17.804951, -63.201005),
    LatLng(-17.811313, -63.208140),
    LatLng(-17.797780, -63.215502),
  ],
  'REMANZO': [
    LatLng(-17.724889, -63.165691),
    LatLng(-17.719933, -63.180131),
    LatLng(-17.689720, -63.169008),
    LatLng(-17.711042, -63.160308),
    LatLng(-17.693484, -63.159644),
    LatLng(-17.694234, -63.159374),
    LatLng(-17.688576, -63.145079),
    LatLng(-17.680974, -63.137453),
    LatLng(-17.671336, -63.143441),
    LatLng(-17.679591, -63.153783),
    LatLng(-17.683351, -63.158864),
  ],
  'NORTE': [
    LatLng(-17.750313, -63.180868),
    LatLng(-17.774793, -63.184295),
    LatLng(-17.774496, -63.176116),
    LatLng(-17.752242, -63.163887),
  ],
  'SUR': [
    LatLng(-17.820, -63.180),
    LatLng(-17.825, -63.165),
    LatLng(-17.840, -63.170),
    LatLng(-17.845, -63.185),
    LatLng(-17.830, -63.195),
  ],
  'URUBO_NORTE': [
    LatLng(-17.763169, -63.217908),
    LatLng(-17.732469, -63.213667),
    LatLng(-17.726275, -63.231339),
    LatLng(-17.757447, -63.237418),
  ],
  'URUBO_SUR': [
    LatLng(-17.769834, -63.223280),
    LatLng(-17.785518, -63.231056),
    LatLng(-17.764516, -63.243568),
    LatLng(-17.780806, -63.248799),
  ],
};
