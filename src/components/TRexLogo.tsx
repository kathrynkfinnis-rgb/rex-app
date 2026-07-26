import { cn } from "@/lib/utils";

/**
 * T. Rex silhouette wearing a small crown — brand mark for the app.
 * Uses currentColor so it inherits from text-* utilities.
 */
export function TRexLogo({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 64 64"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={cn("h-6 w-6", className)}
      aria-hidden="true"
    >
      {/* Crown */}
      <path
        d="M18 10 L22 15 L26 9 L30 15 L34 10 L34 17 L18 17 Z"
        fill="currentColor"
      />
      <circle cx="22" cy="15" r="1.2" fill="currentColor" />
      <circle cx="30" cy="15" r="1.2" fill="currentColor" />
      {/* T-Rex body */}
      <path
        d="M40 20 C44 20 48 24 48 30 L48 34 L52 34 L54 38 L48 38 L48 42 L44 46 L44 52 L40 52 L40 46 L34 46 L34 54 L30 54 L30 46 L26 46 C20 46 16 42 16 36 L16 32 C16 26 20 22 26 22 L28 22 L28 18 L34 18 L34 22 Z M42 28 A1.5 1.5 0 1 1 42 28.01 Z M32 40 L36 40 L34 42 Z"
        fill="currentColor"
      />
      {/* Tiny arms */}
      <path
        d="M36 32 L40 34 L38 35 Z"
        fill="currentColor"
        opacity="0.85"
      />
    </svg>
  );
}
