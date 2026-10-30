#!/usr/bin/env bash
# Oracle 19c non-CDB target; Oracle 11.2.0.4/19c source through an existing DB link.
# No NEXTVAL calls: all reported values are DBA_SEQUENCES.LAST_NUMBER.
set -euo pipefail
# Never trace the SQL*Plus login, even if invoked with bash -x.
set +x

usage() {
    cat <<'USAGE'
Usage:
  align_sequences.sh -host HOST -port PORT -service SERVICE -user USER \
                     -dblink SOURCE_LINK [-ignore-users USER1,USER2] \
                     [-align] [-output FILE] [-sysdba]

  -host       Target database host/SCAN name, IPv4, or [IPv6] address.
  -port       Target listener port (1-65535).
  -service    Target database service name.
  -user       Target login; SQL*Plus prompts for its password.
  -dblink     Existing private/public link from target to source, no leading @.
  -ignore-users  Comma-separated users to exclude in addition to default EXFSYS.
  -align      Report and generate ALTER SEQUENCE statements; never execute them.
  -output     Report or SQL output file (default: timestamped file in this directory).
  -sysdba     Connect AS SYSDBA (required when -user SYS).
  -help       Show this help. Double-dash forms are also accepted.

Default: report only. Neither database's sequences are advanced by reporting.
Values/statuses compare LAST_NUMBER (stored cache boundaries), NOT the last
issued value. For descending sequences, lagging/ahead follow INCREMENT BY.
Generate ALTER statements for eligible lagging non-cycling sequences and unequal
cycling sequences, using the source boundary. Equal sequences and ahead non-cycling
sequences remain unchanged. Cycling sequences must have matching definitions;
unequal cycling positions have status different, not lagging/ahead.
Other sequence settings are preserved.
EXFSYS is always excluded. Additional ignored names use unquoted Oracle identifier
syntax, are converted to uppercase, and may have spaces around the commas.

Both modes only read metadata. Progress stages and query timings are displayed.
Stop consumers on BOTH databases / ALL RAC instances before generating the final
plan and manually executing it. Regenerate stale plans. ALTER SEQUENCE commits.

Required reads: target DBA_USERS, DBA_SEQUENCES, DBA_OBJECTS, V_$DATABASE;
source link account DBA_SEQUENCES (11.2.0.4 and 19c supported). No ALTER privilege
is needed to generate SQL. Manual execution needs ALTER on the target sequences
or ALTER ANY SEQUENCE. NEXTVAL is never called.

Exit: 0 = report/generation complete; 1 = database/OS error;
      2 = usage/environment error; 3 = missing/unsupported/unresolved sequence.
USAGE
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

db_host='' db_port='' db_service='' db_user='' db_link=''
output_file=''
ignored_users_csv='EXFSYS'
do_align=N
as_sysdba=N
while (($#)); do
    case "$1" in
        -help|--help|-h) usage; exit 0 ;;
        -align|--align) do_align=Y; shift ;;
        -sysdba|--sysdba) as_sysdba=Y; shift ;;
        -host|--host|-port|--port|-service|--service|-user|--user|-dblink|--dblink|-output|--output|-ignore-users|--ignore-users)
            (($# >= 2)) || die "Missing value for $1."
            [[ -n $2 && $2 != -* ]] || die "Missing value for $1."
            case "$1" in
                -host|--host) db_host=$2 ;;
                -port|--port) db_port=$2 ;;
                -service|--service) db_service=$2 ;;
                -user|--user) db_user=$2 ;;
                -dblink|--dblink) db_link=$2 ;;
                -output|--output) output_file=$2 ;;
                -ignore-users|--ignore-users) ignored_users_csv+=",$2" ;;
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
# Keep ignored names as separate validated literals, rather than interpolating
# arbitrary CSV into a SQL predicate. One literal per SQL line also permits long
# lists without exceeding SQL*Plus substitution/command-line lengths.
[[ $ignored_users_csv != *$'\n'* && $ignored_users_csv != *$'\r'* &&
   $ignored_users_csv != *, ]] || die 'Invalid ignored-user list: empty entry or newline.'
IFS=',' read -r -a ignored_users <<< "$ignored_users_csv"
ignored_users_csv=''
for ignored_index in "${!ignored_users[@]}"; do
    ignored_name=${ignored_users[ignored_index]}
    ignored_name=${ignored_name#"${ignored_name%%[![:space:]]*}"}
    ignored_name=${ignored_name%"${ignored_name##*[![:space:]]}"}
    [[ $ignored_name =~ ^[a-zA-Z][a-zA-Z0-9_\$#]*$ && ${#ignored_name} -le 128 ]] ||
        die 'Ignored users must be nonempty unquoted Oracle names (up to 128 characters).'
    ignored_users[ignored_index]=$ignored_name
    ignored_users_csv+="${ignored_users_csv:+,}$ignored_name"
done
if [[ $db_user =~ ^[sS][yY][sS]$ && $as_sysdba != Y ]]; then
    die 'Connecting as SYS requires -sysdba.'
fi
if [[ -z $output_file ]]; then
    if [[ $do_align == Y ]]; then
        output_file="sequence_alignment_$(date +%Y%m%d_%H%M%S)_$$.sql"
    else
        output_file="sequence_report_$(date +%Y%m%d_%H%M%S)_$$.txt"
    fi
fi
[[ $output_file != *$'\n'* && $output_file != *$'\r'* ]] || die 'Output path contains a newline.'
[[ ! -e $output_file && ! -L $output_file ]] || die "Output already exists: $output_file"
output_parent=.
if [[ $output_file == */* ]]; then output_parent=${output_file%/*}; fi
[[ -n $output_parent ]] || output_parent=/
[[ -d $output_parent && -w $output_parent ]] || die "Output directory is not writable: $output_parent"

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
printf "define source_link = '%s'\ndefine align_mode = '%s'\ndefine run_dir = '%s'\n" \
    "$db_link" "$do_align" "$run_dir" > "$run_dir/run.sql"
cat >> "$run_dir/run.sql" <<'SQL'
set termout on echo off verify off feedback off heading off pagesize 0
set linesize 32767 trimout on trimspool on tab off recsep off
set serveroutput on size unlimited format wrapped
set arraysize 500 timing on define on
whenever oserror exit 1 rollback
whenever sqlerror exit 1 rollback
variable generate_mode varchar2(1)
variable owners_json clob
variable ignored_users_json clob
variable target_json clob
variable source_json clob
variable scale_expr varchar2(40)
variable shard_expr varchar2(40)
variable session_expr varchar2(40)

prompt -- [1/5] Validate target/link and read eligible target users.
declare
    l_cdb varchar2(3);
    l_links number;
    l_owners number;
    l_ignored json_array_t := json_array_t();
    c_link constant varchar2(128) := upper('&&source_link');
begin
SQL
for ignored_name in "${ignored_users[@]}"; do
    printf "    l_ignored.append(upper('%s'));\n" "$ignored_name" >> "$run_dir/run.sql"
done
cat >> "$run_dir/run.sql" <<'SQL'
    :ignored_users_json := l_ignored.to_clob();
    :generate_mode := '&&align_mode';
    if dbms_db_version.version <> 19 then
        raise_application_error(-20001, 'Target database must be Oracle 19c');
    end if;
    select cdb into l_cdb from v$database;
    if l_cdb <> 'NO' then
        raise_application_error(-20002, 'Target must be a non-CDB database');
    end if;
    select count(*) into l_links from all_db_links
     where db_link = c_link
        or substr(db_link, 1, length(c_link) + 1) = c_link || '.';
    if l_links = 0 then
        raise_application_error(-20003, 'No visible database link named ' || c_link);
    end if;
    select count(*), json_arrayagg(username order by username returning clob)
      into l_owners, :owners_json
      from dba_users where oracle_maintained = 'N'
       and not exists (
           select 1 from json_table(:ignored_users_json, '$[*]' columns (
               username varchar2(128) path '$')) ignored
            where ignored.username = dba_users.username
       );
    if :owners_json is null then :owners_json := '[]'; end if;
    dbms_output.put_line('-- Target: ' || sys_context('USERENV', 'DB_NAME') ||
        '; service: ' || sys_context('USERENV', 'SERVICE_NAME') || '; source link: ' || c_link);
    dbms_output.put_line('-- Eligible target users: ' || l_owners);
    dbms_output.put_line('-- READ ONLY: no sequence values or definitions will be changed.');
end;
/

prompt -- [2/5] Read target sequence metadata once (local query).
declare
    l_rows number;
begin
    -- TARGET_INVENTORY_BEGIN
    select count(*), json_arrayagg(json_object(
               'OWNER' value q.sequence_owner, 'NAME' value q.sequence_name,
               'VALUE' value q.last_number, 'INCREMENT' value q.increment_by,
               'MIN' value q.min_value, 'MAX' value q.max_value,
               'CACHE' value q.cache_size, 'CYCLE' value q.cycle_flag,
               'SCALE' value q.scale_flag, 'SHARD' value q.sharded_flag,
               'SESSION' value q.session_flag, 'GENERATED' value o.generated,
               'MAINTAINED' value o.oracle_maintained, 'OBJECT_ID' value o.object_id
               returning clob) returning clob)
      into l_rows, :target_json
      from dba_sequences q
      join json_table(:owners_json, '$[*]' columns (
          username varchar2(128) path '$')) u on u.username = q.sequence_owner
      left join dba_objects o
        on o.owner = q.sequence_owner and o.object_name = q.sequence_name
       and o.object_type = 'SEQUENCE' and o.subobject_name is null;
    -- TARGET_INVENTORY_END
    if :target_json is null then :target_json := '[]'; end if;
    dbms_output.put_line('-- Target snapshot complete: ' || l_rows || ' sequences.');
end;
/

prompt -- [3/5] Check source feature columns (three no-row probes; 11g compatible).
declare
    c_link constant varchar2(128) := upper('&&source_link');
    function source_flag(p_column varchar2) return varchar2 is
        l_probe number;
    begin
        execute immediate 'select count(q.' || p_column ||
            ') from dba_sequences@' || c_link || ' q where 1 = 0' into l_probe;
        dbms_output.put_line('-- Source ' || p_column || ': present.');
        return 'q.' || p_column;
    exception
        when others then
            if sqlcode = -904 then
                dbms_output.put_line('-- Source ' || p_column || ': absent; using N (legacy source).');
                return '''N''';
            end if;
            raise;
    end;
begin
    :scale_expr := source_flag('SCALE_FLAG');
    :shard_expr := source_flag('SHARDED_FLAG');
    :session_expr := source_flag('SESSION_FLAG');
end;
/

prompt -- [4/5] Read source sequence metadata once over the link, filtered by eligible owners.
prompt -- This stage includes network transfer; there are no per-sequence link queries.
declare
    type source_row is record (
        owner_name varchar2(128), sequence_name varchar2(128),
        last_number number, increment_by number, min_value number, max_value number,
        cache_size number, cycle_flag varchar2(1), scale_flag varchar2(1),
        sharded_flag varchar2(1), session_flag varchar2(1)
    );
    type source_rows is table of source_row;
    l_rows source_rows;
    l_sql clob;
    l_filter clob;
    l_owner_count pls_integer := 0;
    l_snapshot json_array_t := json_array_t();
    l_item json_object_t;
    procedure append_filter(p_text varchar2) is
    begin
        dbms_lob.writeappend(l_filter, length(p_text), p_text);
    end;
begin
    -- Build literal owner predicates locally. 11g IN lists allow 1000 entries;
    -- split larger owner sets into OR groups, still in ONE remote query.
    -- Quoting is required for names containing apostrophes; values come from
    -- the target dictionary, not from unvalidated SQL fragments.
    dbms_lob.createtemporary(l_filter, true);
    for r in (select username from json_table(:owners_json, '$[*]' columns (
        username varchar2(128) path '$'))) loop
        if mod(l_owner_count, 1000) = 0 then
            if l_owner_count > 0 then append_filter(') or '); end if;
            append_filter('q.sequence_owner in (');
        else
            append_filter(',');
        end if;
        append_filter('''' || replace(r.username, '''', '''''') || '''');
        l_owner_count := l_owner_count + 1;
    end loop;
    if l_owner_count = 0 then
        append_filter('1 = 0');
    else
        append_filter(')');
    end if;
    l_sql := q'~
        select q.sequence_owner, q.sequence_name, q.last_number, q.increment_by,
               q.min_value, q.max_value, q.cache_size, q.cycle_flag,
               #SOURCE_SCALE_FLAG# scale_flag, #SOURCE_SHARDED_FLAG# sharded_flag,
               #SOURCE_SESSION_FLAG# session_flag
          from dba_sequences@#SOURCE_LINK# q
         where (#OWNER_FILTER#)
    ~';
    l_sql := replace(l_sql, '#SOURCE_SCALE_FLAG#', :scale_expr);
    l_sql := replace(l_sql, '#SOURCE_SHARDED_FLAG#', :shard_expr);
    l_sql := replace(l_sql, '#SOURCE_SESSION_FLAG#', :session_expr);
    l_sql := replace(l_sql, '#OWNER_FILTER#', l_filter);
    l_sql := replace(l_sql, '#SOURCE_LINK#', upper('&&source_link'));
    execute immediate l_sql bulk collect into l_rows;
    -- This loop only serializes the already-fetched snapshot in local memory.
    -- It executes no SELECT, DDL, NEXTVAL, or remote call.
    for i in 1 .. l_rows.count loop
        l_item := json_object_t();
        l_item.put('OWNER', l_rows(i).owner_name);
        l_item.put('NAME', l_rows(i).sequence_name);
        l_item.put('VALUE', l_rows(i).last_number);
        l_item.put('INCREMENT', l_rows(i).increment_by);
        l_item.put('MIN', l_rows(i).min_value);
        l_item.put('MAX', l_rows(i).max_value);
        l_item.put('CACHE', l_rows(i).cache_size);
        l_item.put('CYCLE', l_rows(i).cycle_flag);
        l_item.put('SCALE', l_rows(i).scale_flag);
        l_item.put('SHARD', l_rows(i).sharded_flag);
        l_item.put('SESSION', l_rows(i).session_flag);
        l_snapshot.append(l_item);
    end loop;
    :source_json := l_snapshot.to_clob();
    dbms_output.put_line('-- Source snapshot complete: ' || l_rows.count || ' sequences.');
    dbms_output.put_line('-- Remote work: 3 feature probes + 1 filtered inventory query, independent of sequence count.');
    dbms_lob.freetemporary(l_filter);
end;
/

prompt -- [5/5] Compare snapshots locally and print status / planned SQL for every sequence.
prompt -- No ALTER is executed. No AFTER query is needed because the database is unchanged.
set timing off
column output_line format a32767
column total_value new_value total_seq noprint
column generated_value new_value generated_count noprint
column unchanged_value new_value unchanged_count noprint
column skipped_value new_value skipped_count noprint
column lagging_value new_value lagging_count noprint
column equal_value new_value equal_count noprint
column ahead_value new_value ahead_count noprint
column different_value new_value different_count noprint
column other_value new_value other_count noprint
column exit_value new_value final_exit noprint
define total_seq = 0
define generated_count = 0
define unchanged_count = 0
define skipped_count = 0
define lagging_count = 0
define equal_count = 0
define ahead_count = 0
define different_count = 0
define other_count = 0
define final_exit = 0
spool &&run_dir/plan.sql
select case when :generate_mode = 'Y'
    then '-- GENERATED SQL ONLY: these ALTER statements have NOT been executed.'
    else '-- READ-ONLY STATUS REPORT.' end output_line from dual;
select '-- Target: ' || sys_context('USERENV', 'DB_NAME') || '; service: ' ||
    sys_context('USERENV', 'SERVICE_NAME') || '; generated: ' ||
    to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS TZH:TZM') output_line from dual;
prompt -- Values are LAST_NUMBER cache boundaries, not last issued values.
prompt -- Owner scope: target DBA_USERS.ORACLE_MAINTAINED=N; matching owner/name on source.
select distinct '-- Ignored user: ' || username output_line
  from json_table(:ignored_users_json, '$[*]' columns (
      username varchar2(128) path '$'))
 order by output_line;
select '-- ' || case when :generate_mode = 'Y' then
    'Stop consumers on BOTH databases / ALL RAC instances, regenerate a fresh plan, review, then execute manually on this target.'
    else 'Use -align [-output FILE] to generate SQL without executing it.' end output_line from dual;
select '-- ' || case when :generate_mode = 'Y' then
    'Generate SQL for eligible lagging non-cycling or different cycling positions; equal positions remain unchanged.'
    else 'PHASE,OWNER,NAME,TARGET_LAST_NUMBER,SOURCE_LAST_NUMBER,TARGET_CACHE_SIZE,SOURCE_CACHE_SIZE,STATUS,DETAILS'
    end output_line from dual;
select 'SET DEFINE OFF' || chr(10) || 'SET SQLBLANKLINES ON' || chr(10) ||
       'SET CMDSEP OFF' || chr(10) || 'SET ECHO ON' || chr(10) || 'SET TIMING ON' || chr(10) ||
       'WHENEVER SQLERROR EXIT 1 ROLLBACK' || chr(10) ||
       'WHENEVER OSERROR EXIT 1 ROLLBACK' output_line
  from dual where :generate_mode = 'Y';
prompt -- Cycling positions use equal/different; lagging/ahead apply only to non-cycling sequences.
select '-- Restart DDL commits individually; no batch rollback. Regenerate stale plans.' output_line
  from dual where :generate_mode = 'Y';

-- COMPARISON_BEGIN
with target_rows as (
    select j.*, 1 present from json_table(:target_json, '$[*]' error on error columns (
        owner_name varchar2(128) path '$.OWNER', sequence_name varchar2(128) path '$.NAME',
        val number path '$.VALUE', increment_by number path '$.INCREMENT',
        min_value number path '$.MIN', max_value number path '$.MAX',
        cache_size number path '$.CACHE', cycle_flag varchar2(1) path '$.CYCLE',
        scale_flag varchar2(1) path '$.SCALE', sharded_flag varchar2(1) path '$.SHARD',
        session_flag varchar2(1) path '$.SESSION', generated varchar2(1) path '$.GENERATED',
        maintained varchar2(1) path '$.MAINTAINED', object_id number path '$.OBJECT_ID'
    )) j
), source_rows as (
    select j.*, 1 present from json_table(:source_json, '$[*]' error on error columns (
        owner_name varchar2(128) path '$.OWNER', sequence_name varchar2(128) path '$.NAME',
        val number path '$.VALUE', increment_by number path '$.INCREMENT',
        min_value number path '$.MIN', max_value number path '$.MAX',
        cache_size number path '$.CACHE', cycle_flag varchar2(1) path '$.CYCLE',
        scale_flag varchar2(1) path '$.SCALE', sharded_flag varchar2(1) path '$.SHARD',
        session_flag varchar2(1) path '$.SESSION'
    )) j
), paired as (
    select coalesce(t.owner_name, s.owner_name) owner_name,
           coalesce(t.sequence_name, s.sequence_name) sequence_name,
           t.present t_present, s.present s_present,
           t.val t_value, s.val s_value,
           t.increment_by t_increment, s.increment_by s_increment,
           t.min_value t_min, s.min_value s_min, t.max_value t_max, s.max_value s_max,
           t.cache_size t_cache, s.cache_size s_cache,
           t.cycle_flag t_cycle, s.cycle_flag s_cycle,
           t.scale_flag t_scale, s.scale_flag s_scale,
           t.sharded_flag t_shard, s.sharded_flag s_shard,
           t.session_flag t_session, s.session_flag s_session,
           t.generated t_generated, t.maintained t_maintained, t.object_id t_object_id
      from target_rows t full outer join source_rows s
        on t.owner_name = s.owner_name and t.sequence_name = s.sequence_name
), classified as (
    select p.*,
        case when t_cycle = 'Y' and s_cycle = 'Y' then s_value
             when t_increment > 0 then greatest(t_value, s_value)
             else least(t_value, s_value) end restart_value,
        case when t_present is null then 'missing_target'
             when s_present is null then 'missing_source'
             when t_session = 'Y' or s_session = 'Y' or t_scale = 'Y' or s_scale = 'Y'
               or t_shard = 'Y' or s_shard = 'Y' then 'unsupported'
             when t_increment <> s_increment or t_cycle <> s_cycle then 'incompatible'
             when t_value is null or s_value is null then 'unavailable'
             when t_value = s_value then 'equal'
             when t_cycle = 'Y' and s_cycle = 'Y' then 'different'
             when (t_increment > 0 and t_value < s_value)
               or (t_increment < 0 and t_value > s_value) then 'lagging'
             else 'ahead' end status
      from paired p
), planned as (
    select c.*,
        case when t_present is null then 'No target sequence; not created'
             when s_present is null then 'No source sequence for eligible target user'
             when t_session = 'Y' or s_session = 'Y' then 'Session sequence: LAST_NUMBER is not meaningful'
             when t_scale = 'Y' or s_scale = 'Y' or t_shard = 'Y' or s_shard = 'Y'
                  then 'Scalable/sharded sequence: not a comparable global counter'
             when t_cycle <> s_cycle then 'Different CYCLE/NOCYCLE definitions'
             when t_increment <> s_increment then 'Different INCREMENT BY definitions'
             when t_min <> s_min or t_max <> s_max then 'Different MINVALUE/MAXVALUE definitions'
             when t_generated = 'Y' then 'System-generated/identity sequence; cannot ALTER SEQUENCE'
             when t_maintained = 'Y' then 'Oracle-maintained object'
             when t_object_id is null then 'Target object metadata unavailable'
             when t_value is null or s_value is null then 'LAST_NUMBER unavailable'
             when restart_value < t_min or restart_value > t_max then 'Restart boundary outside bounds (possibly exhausted)'
             when instr(owner_name, chr(10)) > 0 or instr(owner_name, chr(13)) > 0
               or instr(sequence_name, chr(10)) > 0 or instr(sequence_name, chr(13)) > 0
                  then 'Identifier contains a newline; manual review required'
             else null end issue,
        '"' || replace(owner_name, '"', '""') || '"."' ||
               replace(sequence_name, '"', '""') || '"' quoted_name,
        row_number() over (order by owner_name, sequence_name) seq_no,
        count(*) over () total
      from classified c
), display_rows as (
    select p.*,
        replace(replace(replace(quoted_name, chr(13), '\r'), chr(10), '\n'), chr(9), '\t') display_name,
        to_char(t_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') target_text,
        to_char(s_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') source_text,
        to_char(restart_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') restart_text
      from planned p
)
select case when :generate_mode = 'Y' then
        '-- [' || seq_no || '/' || total || '] ' || display_name ||
        ' | target=' || target_text || ' | source=' || source_text || ' | status=' || status ||
        chr(10) || case when issue is not null then '-- SKIPPED: ' || issue
            when status in ('lagging', 'different') then
            '-- PLANNED: restart at ' || restart_text || case status
                when 'different' then ' (cycling sequence differs; use source stored boundary).'
                else ' (source boundary is farther along).' end || chr(10) ||
            'PROMPT [' || seq_no || '/' || total || '] ' || display_name || ' -> restart at ' || restart_text || chr(10) ||
            'ALTER SEQUENCE ' || quoted_name || ' RESTART START WITH ' || restart_text || ';'
            else '-- UNCHANGED: ' || case status
                when 'equal' then 'stored boundaries are equal; no ALTER is necessary.'
                when 'ahead' then 'target is ahead of source; no ALTER is necessary.'
                else 'no alignment required.' end end
       else replace(replace(replace(
            'REPORT,"' || replace(owner_name, '"', '""') || '","' ||
            replace(sequence_name, '"', '""') || '",' || target_text || ',' || source_text || ',' ||
            to_char(t_cache, 'TM9') || ',' || to_char(s_cache, 'TM9') || ',"' || status || '","' || issue || '"',
            chr(13), '\r'), chr(10), '\n'), chr(9), '\t') end output_line,
       to_char(total, 'FM9999999990') total_value,
       to_char(sum(case when :generate_mode = 'Y' and issue is null and status in ('lagging', 'different')
                       then 1 else 0 end) over (), 'FM9999999990') generated_value,
       to_char(sum(case when issue is null and status in ('equal', 'ahead')
                       then 1 else 0 end) over (), 'FM9999999990') unchanged_value,
       to_char(sum(case when issue is not null then 1 else 0 end) over (), 'FM9999999990') skipped_value,
       to_char(sum(case when status = 'lagging' then 1 else 0 end) over (), 'FM9999999990') lagging_value,
       to_char(sum(case when status = 'equal' then 1 else 0 end) over (), 'FM9999999990') equal_value,
       to_char(sum(case when status = 'ahead' then 1 else 0 end) over (), 'FM9999999990') ahead_value,
       to_char(sum(case when status = 'different' then 1 else 0 end) over (), 'FM9999999990') different_value,
       to_char(sum(case when status not in ('lagging', 'equal', 'ahead', 'different')
                       then 1 else 0 end) over (), 'FM9999999990') other_value,
       case when sum(case when issue is not null then 1 else 0 end) over () > 0 then '3' else '0' end exit_value
  from display_rows order by seq_no;
-- COMPARISON_END

prompt -- Summary: total=&total_seq, lagging=&lagging_count, equal=&equal_count, ahead=&ahead_count, cycling_different=&different_count, other=&other_count.
prompt -- Actions: ALTER statements=&generated_count, unchanged=&unchanged_count, skipped/issues=&skipped_count.
prompt -- No ALTER statements were executed by this generator.
prompt -- SEQUENCE REVIEW COMPLETE
spool off
exit &final_exit rollback
SQL

login="${db_user}@\"//${db_host}:${db_port}/${db_service}\""
if [[ $as_sysdba == Y ]]; then
    login+=' as sysdba'
fi
printf 'Connecting to %s:%s/%s as %s; enter the password at the SQL*Plus prompt.\n' \
    "$db_host" "$db_port" "$db_service" "$db_user"
printf 'Ignored users (names are converted to uppercase): %s\n' "$ignored_users_csv"
if [[ $do_align == Y ]]; then
    printf 'Mode: GENERATE SQL ONLY. Planned output: %s\n' "$output_file"
else
    printf 'Mode: READ-ONLY REPORT. Planned output: %s\n' "$output_file"
fi
# No password in argv, environment, or temporary file. -L prevents login retries.
# Do not use -S: keep SQL*Plus's native password prompt visible.
set +e
"$sqlplus_bin" -L "$login" "@$run_dir/run.sql"
sqlplus_status=$?
set -e
if [[ $sqlplus_status == 0 || $sqlplus_status == 3 ]]; then
    if [[ ! -f $run_dir/plan.sql ]] || ! grep -Fxq -- '-- SEQUENCE REVIEW COMPLETE' "$run_dir/plan.sql"; then
        printf 'ERROR: Report/SQL generation did not finish; no output file was published.\n' >&2
        exit 1
    fi
    if (set -o noclobber; cat "$run_dir/plan.sql" > "$output_file"); then
        if [[ $do_align == Y ]]; then
            printf '\nGenerated SQL: %s\nNo ALTER statements were executed.\n' "$output_file"
        else
            printf '\nReport saved: %s\n' "$output_file"
        fi
        if [[ $sqlplus_status == 3 ]]; then
            printf 'Some sequences were skipped or need attention; inspect the output file.\n' >&2
        fi
    else
        printf 'ERROR: Could not write output file: %s\n' "$output_file" >&2
        exit 1
    fi
fi
exit "$sqlplus_status"
