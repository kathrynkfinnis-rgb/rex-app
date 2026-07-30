import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { MapPin, Book, Film, Tv } from "lucide-react";
import { TRexLogo } from "@/components/TRexLogo";

export const Route = createFileRoute("/")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "REX — Rex from friends you trust" },
      { name: "description", content: "The little shared book of restaurants, books, movies and shows your friends actually love." },
      { property: "og:title", content: "REX — Rex from friends you trust" },
      { property: "og:description", content: "The little shared book of restaurants, books, movies and shows your friends actually love." },
    ],
  }),
  component: Landing,
});

function Landing() {
  const navigate = useNavigate();
  const [checking, setChecking] = useState(true);
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      if (data.user) navigate({ to: "/feed", replace: true });
      else setChecking(false);
    });
  }, [navigate]);

  if (checking) {
    return <div className="min-h-screen bg-background" />;
  }

  return (
    <main className="relative min-h-screen overflow-hidden bg-background">
      <div className="pointer-events-none absolute -right-24 -top-24 h-72 w-72 rounded-full bg-primary/15 blur-3xl" />
      <div className="pointer-events-none absolute -left-24 top-1/2 h-72 w-72 rounded-full bg-accent/20 blur-3xl" />

      <div className="relative mx-auto flex min-h-screen max-w-md flex-col px-6 pb-10 pt-16">
        <div className="flex items-center gap-2 text-sm font-semibold uppercase tracking-widest text-primary">
          <TRexLogo className="h-5 w-5" /> REX
        </div>

        <h1 className="mt-10 font-display text-5xl leading-[1.05] text-foreground">
          The little shared book of things your friends&nbsp;
          <em className="text-primary">actually</em> love.
        </h1>
        <p className="mt-5 text-lg leading-relaxed text-muted-foreground">
          Save the restaurant, the book, the movie, the show. Your friends see it,
          you see theirs. That's it. No algorithm, no strangers.
        </p>

        <div className="mt-8 grid grid-cols-4 gap-2">
          {[
            { i: MapPin, l: "Places" },
            { i: Book, l: "Books" },
            { i: Film, l: "Movies" },
            { i: Tv, l: "TV" },
          ].map(({ i: Icon, l }) => (
            <div key={l} className="flex flex-col items-center gap-1.5 rounded-2xl bg-card p-3 ring-1 ring-border">
              <Icon className="h-5 w-5 text-primary" />
              <span className="text-xs font-medium">{l}</span>
            </div>
          ))}
        </div>

        <div className="mt-auto space-y-3 pt-12">
          <Link
            to="/auth"
            search={{ mode: "signup" as const }}
            className="flex h-14 items-center justify-center rounded-full bg-primary text-base font-semibold text-primary-foreground shadow-lg shadow-primary/30 transition-transform active:scale-[0.98]"
          >
            Get started
          </Link>
          <Link
            to="/auth"
            search={{ mode: "signin" as const }}
            className="flex h-14 items-center justify-center rounded-full border border-border bg-card text-base font-semibold text-foreground"
          >
            I already have an account
          </Link>
        </div>
      </div>
    </main>
  );
}
