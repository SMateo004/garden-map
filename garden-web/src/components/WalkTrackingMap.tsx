/**
 * WalkTrackingMap — Mapa interactivo con ruta GPS del paseo.
 *
 * - Carga la ruta histórica via GET /api/bookings/:id/track
 * - Si el servicio está IN_PROGRESS, se conecta via Socket.io para actualizaciones en tiempo real
 * - Muestra una polilínea de la ruta recorrida + marcador de posición actual
 * - Funciona en modo lectura también para paseos COMPLETED (muestra la ruta completa)
 */
import { useEffect, useRef, useState } from 'react';
import { MapContainer, TileLayer, Polyline, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { io, Socket } from 'socket.io-client';
import { api, getStoredToken } from '@/api/client';

// Fix Leaflet default icon paths broken by bundlers
import iconUrl from 'leaflet/dist/images/marker-icon.png';
import iconRetinaUrl from 'leaflet/dist/images/marker-icon-2x.png';
import shadowUrl from 'leaflet/dist/images/marker-shadow.png';

// Apply fix once
delete (L.Icon.Default.prototype as any)._getIconUrl;
L.Icon.Default.mergeOptions({ iconUrl, iconRetinaUrl, shadowUrl });

/** Custom icon for the live/current position marker */
const liveIcon = L.divIcon({
    html: `<div style="
        width:18px;height:18px;
        background:#22c55e;
        border:3px solid white;
        border-radius:50%;
        box-shadow:0 0 0 3px rgba(34,197,94,0.4);
    "></div>`,
    className: '',
    iconSize: [18, 18],
    iconAnchor: [9, 9],
});

/** Custom icon for start position */
const startIcon = L.divIcon({
    html: `<div style="
        width:14px;height:14px;
        background:#3b82f6;
        border:3px solid white;
        border-radius:50%;
        box-shadow:0 2px 4px rgba(0,0,0,0.3);
    "></div>`,
    className: '',
    iconSize: [14, 14],
    iconAnchor: [7, 7],
});

interface GpsPoint {
    lat: number;
    lng: number;
    timestamp?: string;
    accuracy?: number;
}

interface WalkTrackingMapProps {
    bookingId: string;
    status: string; // BookingStatus as string
    height?: string;
}

/** Auto-pans the map when a new live point arrives */
function LivePanner({ point }: { point: [number, number] | null }) {
    const map = useMap();
    useEffect(() => {
        if (point) map.panTo(point, { animate: true });
    }, [point, map]);
    return null;
}

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:3000';

export function WalkTrackingMap({ bookingId, status, height = '320px' }: WalkTrackingMapProps) {
    const [route, setRoute] = useState<GpsPoint[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const socketRef = useRef<Socket | null>(null);
    const isLive = status === 'IN_PROGRESS';

    // Load initial route from REST
    useEffect(() => {
        let cancelled = false;
        setLoading(true);
        setError(null);

        api.get(`/api/bookings/${bookingId}/track`)
            .then((res) => {
                if (!cancelled) setRoute(res.data.data ?? []);
            })
            .catch(() => {
                if (!cancelled) setError('No se pudo cargar la ruta GPS');
            })
            .finally(() => {
                if (!cancelled) setLoading(false);
            });

        return () => { cancelled = true; };
    }, [bookingId]);

    // Subscribe to live Socket.io updates when IN_PROGRESS
    useEffect(() => {
        if (!isLive) return;

        const token = getStoredToken();
        const socket = io(API_BASE, {
            auth: { token },
            transports: ['websocket'],
            reconnectionAttempts: 5,
        });
        socketRef.current = socket;

        socket.on('connect', () => {
            socket.emit('join_booking', { bookingId });
        });

        socket.on('gps_update', (data: GpsPoint) => {
            if (data && typeof data.lat === 'number' && typeof data.lng === 'number') {
                setRoute((prev) => [...prev, data]);
            }
        });

        return () => {
            socket.disconnect();
            socketRef.current = null;
        };
    }, [bookingId, isLive]);

    if (loading) {
        return (
            <div style={{ height }} className="flex items-center justify-center bg-gray-100 dark:bg-gray-800 rounded-2xl">
                <span className="text-sm text-gray-400 animate-pulse">Cargando mapa…</span>
            </div>
        );
    }

    if (error || route.length === 0) {
        return (
            <div style={{ height }} className="flex flex-col items-center justify-center bg-gray-100 dark:bg-gray-800 rounded-2xl gap-2">
                <span className="text-3xl">{status === 'IN_PROGRESS' ? '🛰️' : '🗺️'}</span>
                <span className="text-sm text-gray-400">
                    {status === 'IN_PROGRESS'
                        ? 'Esperando primera ubicación GPS…'
                        : error ?? 'No hay datos de ruta disponibles'}
                </span>
            </div>
        );
    }

    const positions: [number, number][] = route.map((p) => [p.lat, p.lng]);
    const currentPos = positions[positions.length - 1] ?? null;
    const startPos = positions[0] ?? null;
    // Center on last known position or middle of route
    const center = currentPos ?? [positions[Math.floor(positions.length / 2)]![0], positions[Math.floor(positions.length / 2)]![1]];

    return (
        <div className="rounded-2xl overflow-hidden border border-gray-200 dark:border-gray-700 shadow-sm">
            {isLive && (
                <div className="flex items-center gap-2 px-4 py-2 bg-green-50 dark:bg-green-900/30 border-b border-green-100 dark:border-green-800">
                    <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
                    <span className="text-xs font-bold text-green-700 dark:text-green-400 uppercase tracking-wide">
                        GPS en vivo · {route.length} punto{route.length !== 1 ? 's' : ''} registrado{route.length !== 1 ? 's' : ''}
                    </span>
                </div>
            )}
            {!isLive && route.length > 0 && (
                <div className="flex items-center gap-2 px-4 py-2 bg-blue-50 dark:bg-blue-900/30 border-b border-blue-100 dark:border-blue-800">
                    <span className="text-xs font-bold text-blue-700 dark:text-blue-400 uppercase tracking-wide">
                        Ruta registrada · {route.length} punto{route.length !== 1 ? 's' : ''}
                    </span>
                </div>
            )}
            <MapContainer
                center={center}
                zoom={16}
                style={{ height, width: '100%' }}
                scrollWheelZoom={false}
            >
                <TileLayer
                    attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                    url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />

                {/* Route polyline */}
                {positions.length > 1 && (
                    <Polyline
                        positions={positions}
                        pathOptions={{ color: '#22c55e', weight: 4, opacity: 0.85 }}
                    />
                )}

                {/* Start marker */}
                {startPos && positions.length > 1 && (
                    <Marker position={startPos} icon={startIcon}>
                        <Popup>Inicio del paseo</Popup>
                    </Marker>
                )}

                {/* Current / end position marker */}
                {currentPos && (
                    <Marker position={currentPos} icon={liveIcon}>
                        <Popup>
                            {isLive ? 'Posición actual' : 'Fin del paseo'}
                        </Popup>
                    </Marker>
                )}

                {/* Auto-pan to live position */}
                {isLive && <LivePanner point={currentPos} />}
            </MapContainer>
        </div>
    );
}
