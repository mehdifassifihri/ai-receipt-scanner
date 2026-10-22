-- Run once against a Supabase project using its SQL editor or Supabase CLI.
-- The application never uses a database password. User operations retain RLS.
begin;

create table public.receipts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    storage_path text not null unique,
    sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
    mime_type text not null default 'image/jpeg' check (mime_type = 'image/jpeg'),
    byte_size integer not null check (byte_size > 0 and byte_size <= 6291456),
    created_at timestamptz not null default now(),
    unique (user_id, sha256),
    unique (id, user_id),
    check (storage_path = user_id::text || '/' || id::text || '.jpg')
);

create table public.expenses (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    receipt_id uuid,
    client_request_id uuid not null,
    merchant text not null check (length(btrim(merchant)) between 1 and 120),
    transaction_date date not null check (transaction_date between date '1900-01-01' and (now() at time zone 'UTC')::date),
    amount_in_cents bigint not null check (amount_in_cents between 1 and 99999999999),
    currency text not null check (currency in ('USD', 'EUR', 'MAD', 'CAD', 'GBP')),
    category text not null check (category in ('Food & Drinks', 'Shopping', 'Transport', 'Groceries', 'Health', 'Entertainment', 'Utilities', 'Other')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    foreign key (receipt_id, user_id) references public.receipts(id, user_id) on delete no action deferrable initially deferred,
    unique (user_id, client_request_id),
    unique (receipt_id)
);

create table public.extraction_jobs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    receipt_id uuid not null,
    model text not null,
    prompt_version text not null,
    status text not null default 'processing' check (status in ('processing', 'completed', 'failed')),
    result jsonb,
    error_code text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    foreign key (receipt_id, user_id) references public.receipts(id, user_id) on delete cascade,
    check ((status = 'processing' and result is null and error_code is null)
        or (status = 'completed' and result is not null and error_code is null)
        or (status = 'failed' and result is null and error_code is not null))
);

create index expenses_owner_date on public.expenses(user_id, transaction_date desc, created_at desc, id desc);
create index expenses_owner_currency_date on public.expenses(user_id, currency, transaction_date);
create index extraction_jobs_owner_created on public.extraction_jobs(user_id, created_at);
create index extraction_jobs_receipt_created on public.extraction_jobs(receipt_id, created_at desc);
create unique index extraction_one_active_per_user on public.extraction_jobs(user_id) where status = 'processing';

create function public.set_updated_at() returns trigger language plpgsql set search_path = '' as $$
begin
    new.updated_at = now();
    return new;
end;
$$;
create trigger expenses_updated before update on public.expenses for each row execute function public.set_updated_at();
create trigger extraction_jobs_updated before update on public.extraction_jobs for each row execute function public.set_updated_at();

alter table public.receipts enable row level security;
alter table public.expenses enable row level security;
alter table public.extraction_jobs enable row level security;
revoke all on public.receipts, public.expenses, public.extraction_jobs from anon, authenticated;
grant select, insert, delete on public.receipts to authenticated;
grant select, insert, update, delete on public.expenses to authenticated;
grant select on public.extraction_jobs to authenticated;
grant all on public.receipts, public.expenses, public.extraction_jobs to service_role;

create policy receipts_read_own on public.receipts for select to authenticated using ((select auth.uid()) = user_id);
create policy receipts_insert_own on public.receipts for insert to authenticated with check ((select auth.uid()) = user_id);
create policy receipts_delete_own on public.receipts for delete to authenticated using ((select auth.uid()) = user_id);
create policy expenses_read_own on public.expenses for select to authenticated using ((select auth.uid()) = user_id);
create policy expenses_insert_own on public.expenses for insert to authenticated with check ((select auth.uid()) = user_id);
create policy expenses_update_own on public.expenses for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy expenses_delete_own on public.expenses for delete to authenticated using ((select auth.uid()) = user_id);
create policy extraction_jobs_read_own on public.extraction_jobs for select to authenticated using ((select auth.uid()) = user_id);

-- Atomic cross-worker admission: one active extraction per user, a UTC daily
-- quota, stale-lease recovery, and completed-result caching. Only the backend's
-- service role can call this function or write job state.
create function public.claim_extraction(
    p_user_id uuid, p_receipt_id uuid, p_model text, p_prompt_version text, p_daily_limit integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    v_job public.extraction_jobs;
    v_count bigint;
begin
    if p_daily_limit < 1 or p_daily_limit > 1000 then
        raise exception 'INVALID_DAILY_LIMIT';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
    if not exists (select 1 from public.receipts where id = p_receipt_id and user_id = p_user_id) then
        raise exception 'RECEIPT_NOT_FOUND';
    end if;
    update public.extraction_jobs set status = 'failed', error_code = 'processing_interrupted'
      where user_id = p_user_id and status = 'processing' and updated_at < now() - interval '5 minutes';
    select * into v_job from public.extraction_jobs
      where user_id = p_user_id and receipt_id = p_receipt_id and model = p_model
        and prompt_version = p_prompt_version and status = 'completed'
      order by created_at desc, id desc limit 1;
    if found then
        return jsonb_build_object('cached', true, 'job', to_jsonb(v_job));
    end if;
    if exists (select 1 from public.extraction_jobs where user_id = p_user_id and status = 'processing') then
        raise exception 'EXTRACTION_BUSY';
    end if;
    select count(*) into v_count from public.extraction_jobs
      where user_id = p_user_id and created_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC');
    if v_count >= p_daily_limit then
        raise exception 'EXTRACTION_DAILY_LIMIT';
    end if;
    insert into public.extraction_jobs(user_id, receipt_id, model, prompt_version)
      values(p_user_id, p_receipt_id, p_model, p_prompt_version) returning * into v_job;
    return jsonb_build_object('cached', false, 'job', to_jsonb(v_job));
end;
$$;
revoke all on function public.claim_extraction(uuid, uuid, text, text, integer) from public, anon, authenticated;
grant execute on function public.claim_extraction(uuid, uuid, text, text, integer) to service_role;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 6291456, array['image/jpeg', 'image/png'])
on conflict (id) do update set public = false, file_size_limit = 6291456, allowed_mime_types = array['image/jpeg', 'image/png'];

create policy receipt_objects_read_own on storage.objects for select to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy receipt_objects_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy receipt_objects_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);

commit;
