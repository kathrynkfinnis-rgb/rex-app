import { useEffect, useRef, useState } from "react";

type Place = { id: string; title: string; lat: number; lng: number };

declare global {
  interface Window {
    google: any;
    __rexInitMap?: () => void;
    __rexMapsLoading?: Promise<void>;
  }
}

function loadMaps(): Promise<void> {
  if (typeof window === "undefined") return Promise.reject(new Error("no window"));
  if (window.google?.maps) return Promise.resolve();
  if (window.__rexMapsLoading) return window.__rexMapsLoading;
  const key = import.meta.env.VITE_LOVABLE_CONNECTOR_GOOGLE_MAPS_BROWSER_KEY;
  const channel = import.meta.env.VITE_LOVABLE_CONNECTOR_GOOGLE_MAPS_TRACKING_ID;
  if (!key) return Promise.reject(new Error("Missing Google Maps browser key"));
  window.__rexMapsLoading = new Promise<void>((resolve, reject) => {
    window.__rexInitMap = () => resolve();
    const s = document.createElement("script");
    s.src = `https://maps.googleapis.com/maps/api/js?key=${key}&loading=async&callback=__rexInitMap${channel ? `&channel=${channel}` : ""}`;
    s.async = true;
    s.defer = true;
    s.onerror = () => reject(new Error("Failed to load Google Maps"));
    document.head.appendChild(s);
  });
  return window.__rexMapsLoading;
}

const MILES_TO_M = 1609.34;

export function GoogleMap({
  places,
  onSelect,
  radiusMiles = 10,
}: {
  places: Place[];
  onSelect?: (id: string) => void;
  radiusMiles?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const userLayerRef = useRef<any[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const [userCentered, setUserCentered] = useState(false);

  useEffect(() => {
    let cancelled = false;
    loadMaps()
      .then(() => {
        if (cancelled || !ref.current) return;
        mapRef.current = new window.google.maps.Map(ref.current, {
          center: { lat: 51.5074, lng: -0.1278 },
          zoom: 3,
          disableDefaultUI: true,
          zoomControl: true,
          clickableIcons: false,
        });
        setReady(true);
      })
      .catch((e) => setError(e.message));
    return () => {
      cancelled = true;
    };
  }, []);

  // Centre on the user's own location with a ~10 mile radius when the map opens.
  useEffect(() => {
    if (!ready || !mapRef.current || typeof navigator === "undefined" || !navigator.geolocation) return;
    let cancelled = false;
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        if (cancelled || !mapRef.current || !window.google?.maps) return;
        const center = { lat: pos.coords.latitude, lng: pos.coords.longitude };
        const g = window.google.maps;

        userLayerRef.current.forEach((o) => o.setMap(null));
        userLayerRef.current = [];

        const circle = new g.Circle({
          map: mapRef.current,
          center,
          radius: radiusMiles * MILES_TO_M,
          strokeColor: "#4f7c3a",
          strokeOpacity: 0.5,
          strokeWeight: 1,
          fillColor: "#8ec06c",
          fillOpacity: 0.12,
          clickable: false,
        });
        const dot = new g.Marker({
          map: mapRef.current,
          position: center,
          title: "You",
          zIndex: 999,
          icon: {
            path: g.SymbolPath.CIRCLE,
            scale: 7,
            fillColor: "#2f6f2f",
            fillOpacity: 1,
            strokeColor: "#ffffff",
            strokeWeight: 2,
          },
        });
        userLayerRef.current = [circle, dot];

        mapRef.current.fitBounds(circle.getBounds(), 16);
        setUserCentered(true);
      },
      () => {
        /* denied or unavailable — fall back to fitting the pins */
      },
      { enableHighAccuracy: false, timeout: 8000, maximumAge: 300000 },
    );
    return () => {
      cancelled = true;
    };
  }, [ready, radiusMiles]);

  useEffect(() => {
    if (!ready || !mapRef.current || !window.google?.maps) return;
    markersRef.current.forEach((m) => m.setMap(null));
    markersRef.current = [];
    if (!places.length) return;
    const bounds = new window.google.maps.LatLngBounds();
    places.forEach((p) => {
      const marker = new window.google.maps.Marker({
        position: { lat: p.lat, lng: p.lng },
        map: mapRef.current,
        title: p.title,
      });
      if (onSelect) marker.addListener("click", () => onSelect(p.id));
      markersRef.current.push(marker);
      bounds.extend(marker.getPosition());
    });
    // The user's own 10-mile view wins when we have their location.
    if (userCentered) return;
    if (places.length === 1) {
      mapRef.current.setCenter(bounds.getCenter());
      mapRef.current.setZoom(14);
    } else {
      mapRef.current.fitBounds(bounds, 48);
    }
  }, [places, onSelect, ready, userCentered]);

  if (error) {
    return (
      <div className="flex h-full items-center justify-center p-4 text-center text-sm text-muted-foreground">
        Couldn't load map: {error}
      </div>
    );
  }
  return <div ref={ref} className="h-full w-full" />;
}
