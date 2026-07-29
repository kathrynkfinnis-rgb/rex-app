-- 1. Role enum + table
CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- 2. has_role (security definer to avoid recursion)
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;

-- 3. RLS policies on user_roles
CREATE POLICY "users see own role"
ON public.user_roles FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "admins see all roles"
ON public.user_roles FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- No insert/update/delete policies: only service_role can mutate.

-- 4. Admin KPI function: users & growth
CREATE OR REPLACE FUNCTION public.admin_kpis_users()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT jsonb_build_object(
    'total_users', (SELECT count(*) FROM auth.users),
    'new_24h',    (SELECT count(*) FROM auth.users WHERE created_at >= now() - interval '24 hours'),
    'new_7d',     (SELECT count(*) FROM auth.users WHERE created_at >= now() - interval '7 days'),
    'new_30d',    (SELECT count(*) FROM auth.users WHERE created_at >= now() - interval '30 days'),
    'dau',        (SELECT count(DISTINCT user_id) FROM public.recommendations WHERE created_at >= now() - interval '24 hours'),
    'wau',        (SELECT count(DISTINCT user_id) FROM public.recommendations WHERE created_at >= now() - interval '7 days'),
    'mau',        (SELECT count(DISTINCT user_id) FROM public.recommendations WHERE created_at >= now() - interval '30 days')
  ) INTO result;
  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_kpis_users() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_kpis_users() TO authenticated;

-- 5. Admin KPI function: content activity
CREATE OR REPLACE FUNCTION public.admin_kpis_content()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT jsonb_build_object(
    'recs_total',        (SELECT count(*) FROM public.recommendations),
    'recs_7d',           (SELECT count(*) FROM public.recommendations WHERE created_at >= now() - interval '7 days'),
    'blasts_total',      (SELECT count(*) FROM public.requests),
    'blasts_7d',         (SELECT count(*) FROM public.requests WHERE created_at >= now() - interval '7 days'),
    'rec_comments_total',(SELECT count(*) FROM public.recommendation_comments),
    'rec_comments_7d',   (SELECT count(*) FROM public.recommendation_comments WHERE created_at >= now() - interval '7 days'),
    'blast_comments_total',(SELECT count(*) FROM public.request_comments),
    'blast_comments_7d', (SELECT count(*) FROM public.request_comments WHERE created_at >= now() - interval '7 days'),
    'likes_total',       (SELECT count(*) FROM public.recommendation_likes),
    'likes_7d',          (SELECT count(*) FROM public.recommendation_likes WHERE created_at >= now() - interval '7 days'),
    'saves_total',       (SELECT count(*) FROM public.saved_posts),
    'saves_7d',          (SELECT count(*) FROM public.saved_posts WHERE created_at >= now() - interval '7 days')
  ) INTO result;
  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_kpis_content() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_kpis_content() TO authenticated;

-- 6. Seed first admin (earliest user)
INSERT INTO public.user_roles (user_id, role)
SELECT id, 'admin'::public.app_role
FROM public.profiles
WHERE username = 'kathrynkfinnis'
ON CONFLICT (user_id, role) DO NOTHING;