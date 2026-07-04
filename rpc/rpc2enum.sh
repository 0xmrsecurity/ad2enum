#!/bin/bash
# Usage:-
# ./rpc2enum.sh
# ./rpc2enum.sh [TARGET_IP]
# ./rpc2enum.sh -h | --help
# RPC_USER='USER' RPC_PASS='PASSWORD' ./rpc2enum.sh
# RPC_USER='USER' RPC_PASS='PASSWORD' ./rpc2enum.sh [TARGET_IP]
set -u

# Colors (dark red for [*], dark green for [+])
DRED='\033[38;5;9m'
DGREEN='\033[38;5;46m'
NC='\033[0m'

show_help() {
    cat << EOF
rpc2enum.sh - Anonymous/authenticated RPC enumeration wrapper for rpcclient

USAGE:
    ./rpc2enum.sh [-h|--help] [TARGET_IP]

OPTIONS:
    -h, --help      Show this help message and exit

ARGUMENTS:
    TARGET_IP       IP address of the target (DC/SMB host). If omitted,
                    you will be prompted interactively.

AUTHENTICATION (environment variables, optional):
    RPC_USER        Username for authenticated session (default: anonymous)
    RPC_PASS        Password for authenticated session

EXAMPLES:
    ./rpc2enum.sh
    ./rpc2enum.sh 10.129.60.23
    RPC_USER='j.arbuckle' RPC_PASS='P@ssw0rd' ./rpc2enum.sh
    RPC_USER='j.arbuckle' RPC_PASS='P@ssw0rd' ./rpc2enum.sh 10.129.60.23

WHAT IT RUNS:
    Port check (139/445), srvinfo, lsaquery, querydominfo, enumdomusers,
    enumdomgroups, enumalsgroups, querydispinfo, per-user queryuser,
    lookupnames, RID cycling (lookupsids 500-1100), getdompwinfo,
    netshareenumall, enumprivs, enumprinters.
EOF
}

# Parse args: catch -h/--help before treating anything as the target IP
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
    esac
done

IP="${1:-}"
if [[ -z "$IP" ]]; then
    read -rp "Provide the Target IP address:- " IP
fi

USER="${RPC_USER:-}"        # override with RPC_USER=... ./rpc2enum.sh
PASS="${RPC_PASS:-}"        # override with RPC_PASS=...

if [[ -n "$USER" ]]; then
    # Real credentials supplied -> authenticate properly, no -N
    AUTH=(-U "${USER}%${PASS}")
else
    # No credentials -> fall back to null/anonymous session
    AUTH=(-U "" -N)
fi

section() { echo -e "\n${DGREEN}[+] $1${NC}"; }
banner() { echo -e "${DRED}[*] $1${NC}"; }

run() {
    # run "description" "rpcclient command"
    rpcclient "${AUTH[@]}" "$IP" -c "$2" 2>&1
}

banner "Rpc-client Enumeration script.."
banner "Target: $IP  (auth: '${USER:-anonymous}')"

section "Checking if RPC/SMB port is open (139/445)"
nc -zv -w3 "$IP" 139 2>&1
nc -zv -w3 "$IP" 445 2>&1

section "Server Info (srvinfo)"
run "srvinfo" "srvinfo"

section "Domain / LSA Info (lsaquery)"
run "lsaquery" "lsaquery"

section "Domain Information (querydominfo)"
run "querydominfo" "querydominfo"

section "User Enumeration (enumdomusers)"
USERS_RAW=$(run "enumdomusers" "enumdomusers")
echo "$USERS_RAW"

section "Group Enumeration (enumdomgroups)"
run "enumdomgroups" "enumdomgroups"

section "Alias / Local Group Enumeration (builtin + domain)"
run "enumalsgroups builtin" "enumalsgroups builtin"
run "enumalsgroups domain" "enumalsgroups domain"

section "Display Information (querydispinfo)"
run "querydispinfo" "querydispinfo"

section "Per-user detail (queryuser) for each RID found"
# pull rid:[0x...] out of enumdomusers output and query each one
echo "$USERS_RAW" | grep -oP 'rid:\[\K0x[0-9a-fA-F]+' | while read -r rid; do
    echo "--- RID $rid ---"
    run "queryuser $rid" "queryuser $rid"
done

section "SID Lookup for known usernames (lookupnames)"
echo "$USERS_RAW" | grep -oP 'user:\[\K[^]]+' | while read -r uname; do
    run "lookupnames $uname" "lookupnames $uname"
done

section "RID Cycling / SID brute force (lookupsids, 500-1100)"
DOMSID=$(run "lsaquery" "lsaquery" | grep -oP 'S-1-5-21-[0-9-]+')
if [[ -n "$DOMSID" ]]; then
    echo "Domain SID: $DOMSID"
    for rid in $(seq 500 1100); do
        run "lookupsids $DOMSID-$rid" "lookupsids $DOMSID-$rid" | grep -v -E "NT_STATUS_NONE_MAPPED|\*unknown\*\\\\\*unknown\*"
    done
else
    echo "Could not resolve domain SID, skipping RID cycle."
fi

section "Password Policy Enumeration (getdompwinfo)"
run "getdompwinfo" "getdompwinfo"

section "Shares Enumeration (netshareenumall)"
run "netshareenumall" "netshareenumall"

section "Privileges Enumeration (enumprivs)"
run "enumprivs" "enumprivs"

section "Printer Enumeration (enumprinters)"
run "enumprinters" "enumprinters"
