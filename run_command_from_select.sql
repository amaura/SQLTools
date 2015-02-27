declare
  cursor c is select 'alter user '||username||' identified by toto account unlock' line from dba_users;
begin
  for rec in c loop
    execute immediate rec.line;
  end loop;
end;
/
