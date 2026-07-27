import { cn } from "@/lib/utils";

/**
 * REX brand mark — chunky cartoon T-rex silhouette (🦖-style) wearing a small crown.
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
      {/* Crown sitting on top of the head */}
      <path
        d="M18 6 L23 13 L28 4 L33 13 L38 4 L43 13 L48 6 L48 15 L18 15 Z"
        fill="currentColor"
      />
      <circle cx="23" cy="11" r="1.1" fill="currentColor" />
      <circle cx="33" cy="9" r="1.1" fill="currentColor" />
      <circle cx="43" cy="11" r="1.1" fill="currentColor" />

      {/* Body silhouette — big round head (left), thick tail (right), two chunky legs.
          The eye is an evenodd subpath so it punches a hole in the fill. */}
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M10 30
           C 6 28 6 22 12 20
           C 14 18 18 16 24 16
           C 28 14 36 14 42 18
           C 48 20 54 26 60 40
           L 62 46
           L 56 46
           C 52 42 46 40 42 42
           L 44 54
           L 44 58
           L 38 58
           L 36 54
           L 34 48
           L 30 48
           L 28 54
           L 28 58
           L 22 58
           L 22 54
           L 20 46
           C 16 42 12 38 10 34
           C 7 33 7 31 10 30 Z
           M 16 24
           a 1.7 1.7 0 1 0 0.001 0 Z"
        fill="currentColor"
      />

      {/* Tiny arm in front of the chest */}
      <path
        d="M24 34 q 5 0.5 7 3 l -3 0.2 l 1 1.5 Z"
        fill="currentColor"
        opacity="0.9"
      />

      {/* A couple of small teeth on the snout */}
      <path
        d="M11 31 l 1.4 2 l 1.2 -2 Z M14 31 l 1.2 1.6 l 1 -1.6 Z"
        fill="currentColor"
        opacity="0.75"
      />
    </svg>
  );
}
