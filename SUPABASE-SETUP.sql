-- MADA JOBS : fonctions pour les missions et demandes de retrait simulées.
-- À exécuter dans Supabase > SQL Editor.
-- Les récompenses et retraits sont virtuels : aucun paiement réel n'est effectué.

create or replace function public.complete_task(p_task_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_task public.tasks%rowtype;
  v_count integer;
begin
  if v_user is null then raise exception 'Veuillez vous connecter.'; end if;
  select * into v_task from public.tasks where id = p_task_id and active = true;
  if not found then raise exception 'Mission introuvable ou inactive.'; end if;
  select count(*) into v_count from public.task_completions
   where user_id = v_user and completed_on = current_date;
  if v_count >= 5 then raise exception 'Limite de cinq missions par jour atteinte.'; end if;
  if exists(select 1 from public.task_completions where user_id=v_user and task_id=p_task_id and completed_on=current_date) then
    raise exception 'Cette mission est déjà terminée aujourd’hui.';
  end if;
  insert into public.task_completions(user_id,task_id,completed_on)
  values(v_user,p_task_id,current_date);
  update public.profiles set balance = balance + v_task.reward where id = v_user;
  insert into public.wallet_transactions(user_id,description,amount)
  values(v_user,'Mission : ' || v_task.title,v_task.reward);
end;
$$;

create or replace function public.request_withdrawal(p_amount bigint,p_method text,p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_balance bigint;
begin
  if v_user is null then raise exception 'Veuillez vous connecter.'; end if;
  if p_amount < 20000 then raise exception 'Le retrait minimum est de 20 000 Ar.'; end if;
  if p_method not in ('MVola','Orange Money','Airtel Money') then raise exception 'Moyen de paiement invalide.'; end if;
  if coalesce(length(trim(p_phone)),0) < 8 then raise exception 'Numéro de téléphone invalide.'; end if;
  select balance into v_balance from public.profiles where id=v_user for update;
  if v_balance is null or v_balance < p_amount then raise exception 'Solde virtuel insuffisant.'; end if;
  update public.profiles set balance=balance-p_amount where id=v_user;
  insert into public.withdrawals(user_id,amount,method,phone,status)
  values(v_user,p_amount,p_method,trim(p_phone),'simulated');
  insert into public.wallet_transactions(user_id,description,amount)
  values(v_user,'Demande de retrait simulée',-p_amount);
end;
$$;

revoke all on function public.complete_task(bigint) from public;
revoke all on function public.request_withdrawal(bigint,text,text) from public;
grant execute on function public.complete_task(bigint) to authenticated;
grant execute on function public.request_withdrawal(bigint,text,text) to authenticated;

insert into public.tasks(title,description,reward,active)
select v.title,v.description,100,true
from (values
 ('Découvrir MADA JOBS','Lis les informations et découvre ton espace.'),
 ('Mission observation','Observe attentivement les éléments de la page.'),
 ('Petit défi mémoire','Lis une consigne et retiens les informations.'),
 ('Mission découverte','Découvre une nouvelle rubrique de ton espace.'),
 ('Défi du jour','Termine ta dernière mission quotidienne.')
) as v(title,description)
where not exists(select 1 from public.tasks);
