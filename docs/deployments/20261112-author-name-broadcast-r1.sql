begin;

-- Official Supabase Broadcast from Database, adapted only to the existing
-- work/comment visibility predicates. The payload contains one public work ID.
-- https://supabase.com/docs/guides/realtime/broadcast#trigger-broadcast-messages-from-your-database
-- RDS official example v1.0, upstream 997dafd2a7a29c3c739a00e12fa9a23d7b0e9e83.
-- ZIP SHA256 acb705f6bc2361a8a16195568a602099dc0729b153f1a0e9edb0a80dc5152594.

create or replace function public.community_comment_author_names(p_work_id uuid, p_user_ids uuid[])
returns table(user_id uuid, display_name text)
language plpgsql stable security definer set search_path='' as $$
begin
  if p_user_ids is null or cardinality(p_user_ids) > 200 then
    raise exception 'invalid author selection' using errcode='23514';
  end if;
  if not public.community_comment_work_public(p_work_id) then
    raise exception 'work unavailable' using errcode='42501';
  end if;
  return query
    select p.id, coalesce(p.display_name, '用户')
    from public.profiles p
    where p.id=any(p_user_ids) and exists (
      select 1 from public.comments c
      join public.community_comment_assets a on a.work_id=c.work_id and a.asset_revision=c.asset_revision
      join public.works w on w.id=c.work_id and w.model_storage_path=a.storage_path
      where c.work_id=p_work_id and c.user_id=p.id
        and public.community_comment_projection(c.id) is not null
    );
end $$;
revoke all on function public.community_comment_author_names(uuid,uuid[]) from public,anon,authenticated,service_role;
grant execute on function public.community_comment_author_names(uuid,uuid[]) to anon,authenticated;

create function public.community_comment_name_topic_readable(p_topic text)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
  if p_topic !~ '^community:author-names:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return public.community_comment_work_public(substring(p_topic from 24)::uuid);
end $$;
revoke all on function public.community_comment_name_topic_readable(text) from public,anon,authenticated,service_role;
grant execute on function public.community_comment_name_topic_readable(text) to anon,authenticated;

create policy community_comment_author_names_receive
on realtime.messages for select to anon,authenticated
using (
  extension='broadcast'
  and public.community_comment_name_topic_readable(realtime.topic())
);

create function public.broadcast_community_comment_author_name()
returns trigger language plpgsql security definer set search_path='' as $$
declare affected_work uuid;
begin
  for affected_work in
    select distinct c.work_id
    from public.comments c
    join public.community_comment_assets a on a.work_id=c.work_id and a.asset_revision=c.asset_revision
    join public.works w on w.id=c.work_id and w.model_storage_path=a.storage_path
    where c.user_id=new.id and c.comment_status='published'
      and public.community_comment_work_public(c.work_id)
    union
    select w.id from public.works w
    where w.user_id=new.id and public.community_comment_work_public(w.id)
  loop
    perform realtime.send(
      jsonb_build_object('work_id',affected_work),
      'author_names_changed',
      'community:author-names:'||affected_work::text,
      true
    );
  end loop;
  return null;
end $$;
revoke all on function public.broadcast_community_comment_author_name() from public,anon,authenticated,service_role;
create trigger broadcast_community_comment_author_name
  after update of display_name on public.profiles
  for each row when (old.display_name is distinct from new.display_name)
  execute function public.broadcast_community_comment_author_name();

commit;
