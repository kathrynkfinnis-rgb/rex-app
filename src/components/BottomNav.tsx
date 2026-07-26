import { Link, useRouterState } from "@tanstack/react-router";
import { Home, Map, Plus, Users, User } from "lucide-react";
import { cn } from "@/lib/utils";

const items: { to: "/feed" | "/map" | "/add" | "/friends" | "/me"; icon: typeof Home; label: string; primary?: boolean }[] = [
  { to: "/feed", icon: Home, label: "Feed" },
  { to: "/map", icon: Map, label: "Map" },
  { to: "/add", icon: Plus, label: "Add", primary: true },
  { to: "/friends", icon: Users, label: "Friends" },
  { to: "/me", icon: User, label: "You" },
];

export function BottomNav() {
  const path = useRouterState({ select: (s) => s.location.pathname });
  return (
    <nav className="fixed inset-x-0 bottom-0 z-40 border-t border-border bg-card/95 pb-[env(safe-area-inset-bottom)] backdrop-blur">
      <div className="mx-auto flex max-w-md items-center justify-around px-2 py-2">
        {items.map(({ to, icon: Icon, label, primary }) => {
          const active = path === to;
          if (primary) {
            return (
              <Link
                key={to}
                to={to}
                className="-mt-6 flex h-14 w-14 items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg shadow-primary/30 transition-transform active:scale-95"
                aria-label={label}
              >
                <Icon className="h-6 w-6" strokeWidth={2.5} />
              </Link>
            );
          }
          return (
            <Link
              key={to}
              to={to}
              className={cn(
                "flex flex-1 flex-col items-center gap-1 py-1 text-[11px] font-medium transition-colors",
                active ? "text-primary" : "text-muted-foreground",
              )}
            >
              <Icon className="h-5 w-5" strokeWidth={active ? 2.5 : 2} />
              {label}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
