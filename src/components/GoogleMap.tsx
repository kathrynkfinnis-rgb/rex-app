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

export function GoogleMap({ places, onSelect }: { places: Place[]; onSelect?: (id: string) => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const [error, setError] = useState<string | null>(null);

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
      })
      .catch((e) => setError(e.message));
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!mapRef.current || !window.google?.maps) return;
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
    if (places.length === 1) {
      mapRef.current.setCenter(bounds.getCenter());
      mapRef.current.setZoom(14);
    } else {
      mapRef.current.fitBounds(bounds, 48);
    }
  }, [places, onSelect]);

  if (error) {
    return (
      <div className="flex h-full items-center justify-center p-4 text-center text-sm text-muted-foreground">
        Couldn't load map: {error}
      </div>
    );
  }
  return <div ref={ref} className="h-full w-full" />;
}
