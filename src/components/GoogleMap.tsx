import { useEffect, useRef, useState } from "react";

type Place = {
  id: string;
  title: string;
  lat: number;
  lng: number;
  avatarUrl?: string | null;
  byName?: string | null;
  rating?: number | null;
  note?: string | null;
  subtitle?: string | null;
};

const PIN_W = 52;
const PIN_H = 62;

function initialsOf(name?: string | null) {
  const n = (name || "?").trim();
  const parts = n.split(/\s+/).slice(0, 2);
  return parts.map((p) => p[0]?.toUpperCase() ?? "").join("") || "?";
}

function drawPin(img: HTMLImageElement | null, initials: string): string {
  const dpr = 2;
  const c = document.createElement("canvas");
  c.width = PIN_W * dpr;
  c.height = PIN_H * dpr;
  const ctx = c.getContext("2d")!;
  ctx.scale(dpr, dpr);

  const cx = PIN_W / 2;
  const cy = 24;
  const r = 20;

  // teardrop tail
  ctx.beginPath();
  ctx.moveTo(cx - 9, cy + 15);
  ctx.quadraticCurveTo(cx, PIN_H - 2, cx + 9, cy + 15);
  ctx.closePath();
  ctx.fillStyle = "#4f7c3a";
  ctx.fill();

  // ring
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fillStyle = "#4f7c3a";
  ctx.fill();

  ctx.save();
  ctx.beginPath();
  ctx.arc(cx, cy, r - 3, 0, Math.PI * 2);
  ctx.clip();
  if (img) {
    const s = Math.min(img.width, img.height);
    ctx.drawImage(img, (img.width - s) / 2, (img.height - s) / 2, s, s, cx - (r - 3), cy - (r - 3), (r - 3) * 2, (r - 3) * 2);
  } else {
    ctx.fillStyle = "#e6efdc";
    ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
    ctx.fillStyle = "#31502a";
    ctx.font = "bold 15px system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(initials, cx, cy + 1);
  }
  ctx.restore();
  return c.toDataURL("image/png");
}

const iconCache = new Map<string, Promise<string>>();

function avatarIcon(url: string | null | undefined, name?: string | null): Promise<string> {
  const key = `${url || ""}|${initialsOf(name)}`;
  const cached = iconCache.get(key);
  if (cached) return cached;
  const p = new Promise<string>((resolve) => {
    if (!url) return resolve(drawPin(null, initialsOf(name)));
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => {
      try {
        resolve(drawPin(img, initialsOf(name)));
      } catch {
        resolve(drawPin(null, initialsOf(name)));
      }
    };
    img.onerror = () => resolve(drawPin(null, initialsOf(name)));
    img.src = url;
  });
  iconCache.set(key, p);
  return p;
}

function escapeHtml(s: string) {
  return s.replace(/[&<>"']/g, (ch) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch] as string,
  );
}

function bubbleHtml(p: Place) {
  const crowns = p.rating ? `<div style="font-size:12px;color:#4f7c3a;margin-top:2px">👑 ${p.rating}/10</div>` : "";
  const by = p.byName ? `<div style="font-size:12px;color:#6b7280">Rex by ${escapeHtml(p.byName)}</div>` : "";
  const note = p.note
    ? `<div style="font-size:12px;color:#374151;margin-top:4px;max-width:220px">“${escapeHtml(p.note.slice(0, 160))}${p.note.length > 160 ? "…" : ""}”</div>`
    : "";
  const sub = p.subtitle ? `<div style="font-size:11px;color:#9ca3af">${escapeHtml(p.subtitle)}</div>` : "";
  return `<div style="font-family:system-ui,sans-serif;padding:2px 2px 4px">
    <div style="font-weight:600;font-size:13px;color:#111827">${escapeHtml(p.title)}</div>
    ${sub}${by}${crowns}${note}
    <div style="font-size:11px;color:#9ca3af;margin-top:6px">Tap the pin to open</div>
  </div>`;
}


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
