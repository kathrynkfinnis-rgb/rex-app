ALTER TABLE public.recommendations DROP CONSTRAINT recommendations_user_id_fkey;
ALTER TABLE public.recommendations
  ADD CONSTRAINT recommendations_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.check_ins DROP CONSTRAINT IF EXISTS check_ins_user_id_fkey;
ALTER TABLE public.check_ins
  ADD CONSTRAINT check_ins_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
