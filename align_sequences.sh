#!/usr/bin/env bash
# Oracle 19c non-CDB sequence comparison/alignment through an existing DB link.
# No NEXTVAL calls: all reported values are DBA_SEQUENCES.LAST_NUMBER.
set -euo pipefail
# Never trace the SQL*Plus login, even if invoked with bash -x.
set +x

usage() {
    cat <<'USAGE'
Usage:
  align_sequences.sh -host HOST -port PORT -service SERVICE -user USER \
                     -dblink SOURCE_LINK [-align] [-sysdba]

  -host       Target database host/SCAN name, IPv4, or [IPv6] address.
  -port       Target listener port (1-65535).
  -service    Target database service name.
  -user       Target login; SQL*Plus prompts for its password.
  -dblink     Existing private/public link from target to source, no leading @.
  -align      Report BEFORE, advance eligible target sequences, report AFTER.
  -sysdba     Connect AS SYSDBA (required when -user SYS).
  -help       Show this help. Double-dash forms are also accepted.

Default: report only. Neither database's sequences are advanced by reporting.
Values/statuses compare LAST_NUMBER (stored cache boundaries), NOT the last
issued value. For descending sequences, lagging/ahead follow INCREMENT BY.
Alignment restarts each eligible target at the farther-along target/source
boundary, even if equal/ahead, to discard potentially lower cached values.
No boundary is rewound; other sequence settings are preserved.

Stop sequence consumers on BOTH databases, on ALL RAC instances, before -align.
ALTER SEQUENCE commits; completed changes cannot be rolled back.

Required reads: target DBA_USERS, DBA_SEQUENCES, DBA_OBJECTS, V_$DATABASE;
source link account DBA_USERS and DBA_SEQUENCES. Alignment additionally needs
ALTER on the target sequences or ALTER ANY SEQUENCE. Source sequence grants
and SELECT ANY SEQUENCE are unnecessary because NEXTVAL is never called.

Exit: 0 = report/alignment complete; 1 = database/OS error;
      2 = usage/environment error; 3 = missing/unsupported/unresolved sequence.
USAGE
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

db_host='' db_port='' db_service='' db_user='' db_link=''
do_align=N
as_sysdba=N
while (($#)); do
    case "$1" in
        -help|--help|-h) usage; exit 0 ;;
        -align|--align) do_align=Y; shift ;;
        -sysdba|--sysdba) as_sysdba=Y; shift ;;
        -host|--host|-port|--port|-service|--service|-user|--user|-dblink|--dblink)
            (($# >= 2)) || die "Missing value for $1."
            [[ -n $2 && $2 != -* ]] || die "Missing value for $1."
            case "$1" in
                -host|--host) db_host=$2 ;;
                -port|--port) db_port=$2 ;;
                -service|--service) db_service=$2 ;;
                -user|--user) db_user=$2 ;;
                -dblink|--dblink) db_link=$2 ;;
            esac
            shift 2
            ;;
        *) die "Unknown argument: $1. Use -help." ;;
    esac
done

[[ -n $db_host && -n $db_port && -n $db_service && -n $db_user && -n $db_link ]] || {
    usage >&2
    die 'The -host, -port, -service, -user, and -dblink arguments are required.'
}

# Restrict connection/substitution inputs to their intended syntax. SQL object
# names read from the dictionary are quoted separately inside PL/SQL.
[[ $db_host =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ||
   $db_host =~ ^\[[a-fA-F0-9:]+\]$ ]] || die 'Invalid host name/address.'
[[ $db_port =~ ^[0-9]{1,5}$ ]] || die 'Port must be an integer from 1 to 65535.'
db_port=$((10#$db_port))
((db_port >= 1 && db_port <= 65535)) || die 'Port must be from 1 to 65535.'
[[ $db_service =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.\$#-]*$ ]] || die 'Invalid service name.'
[[ $db_user =~ ^[a-zA-Z][a-zA-Z0-9_\$#]*$ && ${#db_user} -le 128 ]] ||
    die 'Use an unquoted Oracle login name (up to 128 characters).'
[[ $db_link =~ ^[a-zA-Z][a-zA-Z0-9_\$#]*(\.[a-zA-Z0-9_\$#]+)*$ &&
   ${#db_link} -le 128 ]] || die 'Invalid database link name (omit @ and quotes).'
if [[ $db_user =~ ^[sS][yY][sS]$ && $as_sysdba != Y ]]; then
    die 'Connecting as SYS requires -sysdba.'
fi

sqlplus_bin=
if [[ -n ${ORACLE_HOME:-} && -x $ORACLE_HOME/bin/sqlplus ]]; then
    sqlplus_bin=$ORACLE_HOME/bin/sqlplus
elif command -v sqlplus >/dev/null 2>&1; then
    sqlplus_bin=$(command -v sqlplus)
else
    cat >&2 <<'ENVIRONMENT'
ERROR: SQL*Plus could not be found in ORACLE_HOME/bin or PATH.
Source the database environment file in this shell, then rerun this command:

    source /home/oracle/<DB>.env

Replace <DB> with the actual database name (for example: source /home/oracle/PROD.env).
ENVIRONMENT
    exit 2
fi

umask 077
run_dir=$(mktemp -d /tmp/align_sequences.XXXXXXXX) || exit 1
trap 'rm -rf -- "$run_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Arguments are already restricted above; these are the only shell substitutions
# written to SQL. Credentials are handled by SQL*Plus itself and never stored.
printf "define source_link = '%s'\ndefine align_mode = '%s'\n" \
    "$db_link" "$do_align" > "$run_dir/run.sql"
cat >> "$run_dir/run.sql" <<'SQL'
set termout on echo off verify off feedback off heading off pagesize 0
set linesize 32767 trimout on trimspool on tab off
set serveroutput on size unlimited format wrapped
set define on
whenever oserror exit 1 rollback
whenever sqlerror exit 1 rollback
variable run_exit number

declare
    c_link  constant varchar2(128) := upper('&&source_link');
    c_align constant boolean := '&&align_mode' = 'Y';

    type seq_row is record (
        owner_name      varchar2(128),
        sequence_name   varchar2(128),
        t_present       number,         s_present       number,
        t_value         number,         s_value         number,
        t_increment     number,         s_increment     number,
        t_min           number,         s_min           number,
        t_max           number,         s_max           number,
        t_cache         number,         s_cache         number,
        t_cycle         varchar2(1),    s_cycle         varchar2(1),
        t_scale         varchar2(1),    s_scale         varchar2(1),
        t_shard         varchar2(1),    s_shard         varchar2(1),
        t_session       varchar2(1),    s_session       varchar2(1),
        t_generated     varchar2(1),
        t_maintained    varchar2(1),
        t_object_id     number,
        t_last_ddl_time date
    );
    type seq_rows is table of seq_row;
    l_before seq_rows;
    l_after  seq_rows;
    l_now    seq_row;
    l_sql    varchar2(32767);
    l_stmt   varchar2(1000);
    l_cdb    varchar2(3);
    l_status varchar2(30);
    l_reason varchar2(1000);
    l_restart number;
    l_link_count pls_integer;
    l_changed    pls_integer := 0;
    l_issues     pls_integer := 0;
    l_errors     pls_integer := 0;

    function num(p_value number) return varchar2 is
    begin
        return to_char(p_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''');
    end;

    function csv(p_value varchar2) return varchar2 is
    begin
        -- Keep each record on one output line, even for unusual quoted names.
        return '"' || replace(replace(replace(replace(
            p_value, '"', '""'), chr(13), '\r'), chr(10), '\n'), chr(9), '\t') || '"';
    end;

    function quoted(p_name varchar2) return varchar2 is
    begin
        return '"' || replace(p_name, '"', '""') || '"';
    end;

    function status_of(r seq_row) return varchar2 is
    begin
        if r.t_present is null then return 'missing_target'; end if;
        if r.s_present is null then return 'missing_source'; end if;
        if r.t_session = 'Y' or r.s_session = 'Y'
           or r.t_scale = 'Y' or r.s_scale = 'Y'
           or r.t_shard = 'Y' or r.s_shard = 'Y'
           or r.t_cycle = 'Y' or r.s_cycle = 'Y' then
            return 'unsupported';
        end if;
        if r.t_increment <> r.s_increment then return 'incompatible'; end if;
        if r.t_value is null or r.s_value is null then return 'unavailable'; end if;
        if r.t_value = r.s_value then return 'equal'; end if;
        if (r.t_increment > 0 and r.t_value < r.s_value)
           or (r.t_increment < 0 and r.t_value > r.s_value) then
            return 'lagging';
        end if;
        return 'ahead';
    end;

    function restart_at(r seq_row) return number is
    begin
        if r.t_increment > 0 then
            return greatest(r.t_value, r.s_value);
        else
            return least(r.t_value, r.s_value);
        end if;
    end;

    function alignment_issue(r seq_row) return varchar2 is
    begin
        if r.t_present is null then
            return 'No target sequence in a user with ORACLE_MAINTAINED=N; not created';
        elsif r.s_present is null then
            return 'No source sequence in a user with ORACLE_MAINTAINED=N';
        elsif r.t_session = 'Y' or r.s_session = 'Y' then
            return 'Session sequence: LAST_NUMBER is not meaningful';
        elsif r.t_scale = 'Y' or r.s_scale = 'Y'
           or r.t_shard = 'Y' or r.s_shard = 'Y' then
            return 'Scalable/sharded sequence: not a comparable global counter';
        elsif r.t_cycle = 'Y' or r.s_cycle = 'Y' then
            return 'Cycling sequence: lagging/ahead cannot establish cycle position';
        elsif r.t_increment <> r.s_increment then
            return 'Different INCREMENT BY definitions; not altered';
        elsif r.t_min <> r.s_min or r.t_max <> r.s_max then
            return 'Different MINVALUE/MAXVALUE definitions; not altered';
        elsif r.t_generated = 'Y' then
            return 'System-generated/identity sequence; cannot ALTER SEQUENCE';
        elsif r.t_maintained = 'Y' then
            return 'Oracle-maintained object; not altered';
        elsif r.t_object_id is null then
            return 'Target object metadata unavailable; not altered';
        elsif r.t_value is null or r.s_value is null then
            return 'LAST_NUMBER unavailable; not altered';
        elsif restart_at(r) < r.t_min or restart_at(r) > r.t_max then
            return 'Restart boundary outside sequence bounds (possibly exhausted)';
        end if;
        return null;
    end;

    procedure emit_row(p_phase varchar2, r seq_row, p_details varchar2) is
    begin
        dbms_output.put_line(csv(p_phase) || ',' || csv(r.owner_name) || ',' ||
            csv(r.sequence_name) || ',' || num(r.t_value) || ',' || num(r.s_value) || ',' ||
            num(r.t_cache) || ',' || num(r.s_cache) || ',' ||
            csv(status_of(r)) || ',' || csv(p_details));
    end;

    procedure report(p_phase varchar2, p_rows seq_rows) is
        l_lagging pls_integer := 0;
        l_equal   pls_integer := 0;
        l_ahead   pls_integer := 0;
        l_other   pls_integer := 0;
    begin
        dbms_output.put_line('# ' || p_phase);
        dbms_output.put_line('PHASE,OWNER,NAME,TARGET_LAST_NUMBER,SOURCE_LAST_NUMBER,' ||
                             'TARGET_CACHE_SIZE,SOURCE_CACHE_SIZE,STATUS,DETAILS');
        for i in 1 .. p_rows.count loop
            emit_row(p_phase, p_rows(i), alignment_issue(p_rows(i)));
            case status_of(p_rows(i))
                when 'lagging' then l_lagging := l_lagging + 1;
                when 'equal'   then l_equal   := l_equal + 1;
                when 'ahead'   then l_ahead   := l_ahead + 1;
                else l_other := l_other + 1;
            end case;
        end loop;
        dbms_output.put_line('# ' || p_phase || ': total=' || p_rows.count ||
            ', lagging=' || l_lagging || ', equal=' || l_equal ||
            ', ahead=' || l_ahead || ', other=' || l_other);
    end;

begin
    :run_exit := 0;
    if dbms_db_version.version <> 19 then
        raise_application_error(-20001, 'Target database must be Oracle 19c');
    end if;
    select cdb into l_cdb from v$database;
    if l_cdb <> 'NO' then
        raise_application_error(-20002, 'Target must be a non-CDB database');
    end if;
    select count(*) into l_link_count
      from all_db_links
     where db_link = c_link
        or substr(db_link, 1, length(c_link) + 1) = c_link || '.';
    -- A short DB link name may be expanded by Oracle with the local DB domain.
    if l_link_count = 0 then
        raise_application_error(-20003, 'No visible database link named ' || c_link);
    end if;

    -- Filter each side independently. FULL OUTER JOIN also exposes source-only
    -- and target-only sequences instead of silently omitting missing objects.
    -- Source DBA_* access is intentional: ALL_SEQUENCES could hide sequences.
    l_sql := q'~
        select coalesce(t.sequence_owner, s.sequence_owner) owner_name,
               coalesce(t.sequence_name, s.sequence_name) sequence_name,
               t.present, s.present, t.last_number, s.last_number,
               t.increment_by, s.increment_by, t.min_value, s.min_value,
               t.max_value, s.max_value, t.cache_size, s.cache_size,
               t.cycle_flag, s.cycle_flag, t.scale_flag, s.scale_flag,
               t.sharded_flag, s.sharded_flag, t.session_flag, s.session_flag,
               t.generated, t.object_maintained, t.object_id, t.last_ddl_time
          from (
              select q.*, 1 present, o.generated,
                     o.oracle_maintained object_maintained,
                     o.object_id, o.last_ddl_time
                from dba_sequences q
                join dba_users u on u.username = q.sequence_owner
                left join dba_objects o
                  on o.owner = q.sequence_owner and o.object_name = q.sequence_name
                 and o.object_type = 'SEQUENCE' and o.subobject_name is null
               where u.oracle_maintained = 'N'
          ) t
          full outer join (
              select q.*, 1 present
                from dba_sequences@~' || c_link || q'~ q
                join dba_users@~' || c_link || q'~ u on u.username = q.sequence_owner
               where u.oracle_maintained = 'N'
          ) s on s.sequence_owner = t.sequence_owner
             and s.sequence_name = t.sequence_name
    ~';

    dbms_output.put_line('# Target: ' || sys_context('USERENV', 'DB_NAME') ||
        '; service: ' || sys_context('USERENV', 'SERVICE_NAME') || '; source link: ' || c_link);
    dbms_output.put_line('# Values are LAST_NUMBER cache boundaries, NOT last issued values.');
    dbms_output.put_line('# No NEXTVAL calls are made on either database.');
    dbms_output.put_line('# Status follows sequence direction; neither stored boundary is rewound.');
    execute immediate l_sql || ' order by 1, 2' bulk collect into l_before;
    if c_align then
        dbms_output.put_line('# ALIGN: consumers must be stopped on BOTH databases / ALL RAC instances.');
        dbms_output.put_line('# ALTER SEQUENCE commits; there is no batch rollback.');
        report('BEFORE', l_before);
        dbms_output.put_line('# ACTIONS (same CSV columns)');

        for i in 1 .. l_before.count loop
            l_reason := alignment_issue(l_before(i));
            if l_reason is not null then
                l_issues := l_issues + 1;
                emit_row('ACTION', l_before(i), 'SKIPPED: ' || l_reason);
            else
                begin
                    -- Close the bulk-report cursor before DDL, and re-read both
                    -- boundaries and the target definition immediately before it.
                    execute immediate 'select * from (' || l_sql ||
                        ') where owner_name = :owner_name and sequence_name = :seq_name'
                        into l_now using l_before(i).owner_name, l_before(i).sequence_name;
                    if l_now.t_object_id <> l_before(i).t_object_id
                       or l_now.t_last_ddl_time <> l_before(i).t_last_ddl_time
                       or l_now.t_value <> l_before(i).t_value
                       or l_now.s_value <> l_before(i).s_value
                       or alignment_issue(l_now) is not null then
                        l_issues := l_issues + 1;
                        emit_row('ACTION', l_now, 'SKIPPED: metadata/state changed since BEFORE');
                    else
                        -- Even an equal/ahead stored boundary can hide smaller
                        -- unused cached values. Restart at the farther boundary
                        -- to invalidate those ranges without rewinding either side.
                        l_restart := restart_at(l_now);
                        l_stmt := 'alter sequence ' || quoted(l_now.owner_name) || '.' ||
                            quoted(l_now.sequence_name) || ' restart start with ' || num(l_restart);
                        execute immediate l_stmt;
                        l_changed := l_changed + 1;
                        emit_row('ACTION', l_now, 'RESTARTED: next target value set to ' ||
                            num(l_restart) || '; verify in AFTER');
                    end if;
                exception
                    when others then
                        l_errors := l_errors + 1;
                        emit_row('ACTION', l_before(i), 'ERROR: ' || sqlerrm);
                end;
            end if;
        end loop;

        execute immediate l_sql || ' order by 1, 2' bulk collect into l_after;
        report('AFTER', l_after);
    else
        report('REPORT', l_before);
        l_after := l_before;
    end if;

    -- Report unresolved states even if there were no eligible ALTER statements.
    -- In align mode, unsupported objects cannot have their cached ranges flushed.
    for i in 1 .. l_after.count loop
        l_status := status_of(l_after(i));
        if l_status not in ('lagging', 'equal', 'ahead')
           or alignment_issue(l_after(i)) is not null
           or (c_align and l_status = 'lagging') then
            l_issues := l_issues + 1;
        end if;
    end loop;
    if l_errors > 0 then
        :run_exit := 1;
    elsif l_issues > 0 then
        :run_exit := 3;
    end if;
    dbms_output.put_line('# Completed: altered=' || l_changed ||
        ', errors=' || l_errors || ', exit=' || :run_exit);
exception
    when others then
        dbms_output.put_line('# FATAL: ' || sqlerrm);
        raise;
end;
/
exit :run_exit rollback
SQL

login="${db_user}@\"//${db_host}:${db_port}/${db_service}\""
if [[ $as_sysdba == Y ]]; then
    login+=' as sysdba'
fi
printf 'Connecting to %s:%s/%s as %s; enter the password at the SQL*Plus prompt.\n' \
    "$db_host" "$db_port" "$db_service" "$db_user"
# No password in argv, environment, or temporary file. -L prevents login retries.
# Do not use -S: keep SQL*Plus's native password prompt visible.
set +e
"$sqlplus_bin" -L "$login" "@$run_dir/run.sql"
sqlplus_status=$?
set -e
exit "$sqlplus_status"
