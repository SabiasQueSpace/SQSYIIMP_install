#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#
# System health check for Yiimpool
#
# Author: SabiasQue.Space
# Date: 2024-07-15
#####################################################

source /etc/functions.sh
source /etc/yiimpool.conf
source /etc/yiimpoolversion.conf
source "$STORAGE_ROOT/yiimp/.yiimp.conf"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo -e "  ${GREEN}[✓] $service is running${NC}"
    else
        echo -e "  ${RED}[✗] $service is not running${NC}"
    fi
}

check_disk_space() {
    print_header "Disk Space Usage"
    df -h / | awk 'NR==1 {printf "  %s\n", $0}; NR==2 {
        used=$5;
        sub(/%/,"",used);
        if (used > 90)
            printf "  '"${RED}"'%s'"${NC}"'\n", $0;
        else if (used > 75)
            printf "  '"${YELLOW}"'%s'"${NC}"'\n", $0;
        else
            printf "  '"${GREEN}"'%s'"${NC}"'\n", $0;
    }'
}

check_swap() {
    print_header "Swap Usage"
    local swap_total swap_used swap_percent
    swap_total=$(free -m | awk 'NR==3 {print $2}')
    if [ "${swap_total:-0}" -eq 0 ]; then
        echo -e "  ${YELLOW}[!] No swap space configured${NC}"
        return
    fi
    swap_used=$(free -m | awk 'NR==3 {print $3}')
    swap_percent=$(free | awk 'NR==3 {if($2>0) printf "%.1f", $3/$2*100; else print "0"}')
    if (( $(echo "$swap_percent > 80" | bc -l) )); then
        echo -e "  ${RED}Swap Used: ${swap_used}M / ${swap_total}M (${swap_percent}%)${NC}"
    elif (( $(echo "$swap_percent > 50" | bc -l) )); then
        echo -e "  ${YELLOW}Swap Used: ${swap_used}M / ${swap_total}M (${swap_percent}%)${NC}"
    else
        echo -e "  ${GREEN}Swap Used: ${swap_used}M / ${swap_total}M (${swap_percent}%)${NC}"
    fi
}

check_memory() {
    print_header "Memory Usage"
    local total used free_mem buffers available used_percent color
    total=$(free -m    | awk 'NR==2 {printf "%.1f", $2/1024}')
    used=$(free -m     | awk 'NR==2 {printf "%.1f", $3/1024}')
    free_mem=$(free -m | awk 'NR==2 {printf "%.1f", $4/1024}')
    buffers=$(free -m  | awk 'NR==2 {printf "%.1f", $6/1024}')
    available=$(free -m| awk 'NR==2 {printf "%.1f", $7/1024}')
    used_percent=$(free | awk 'NR==2 {printf "%.1f", $3/$2*100}')

    if (( $(echo "$used_percent > 90" | bc -l) )); then
        color=$RED
    elif (( $(echo "$used_percent > 75" | bc -l) )); then
        color=$YELLOW
    else
        color=$GREEN
    fi

    echo -e "  Total Memory:     ${total}G"
    echo -e "  Used Memory:      ${color}${used}G (${used_percent}%)${NC}"
    echo -e "  Free Memory:      ${GREEN}${free_mem}G${NC}"
    echo -e "  Buff/Cache:       ${buffers}G"
    echo -e "  Available Memory: ${GREEN}${available}G${NC}"
}

check_load() {
    print_header "System Load & Uptime"
    local load1 load5 load15 cpu_count color
    read -r load1 load5 load15 _ < /proc/loadavg
    cpu_count=$(nproc)

    # Warn if 1-minute load exceeds the number of CPU cores
    if (( $(echo "$load1 > $cpu_count" | bc -l) )); then
        color=$RED
    elif (( $(echo "$load1 > $(echo "$cpu_count * 0.75" | bc -l)" | bc -l) )); then
        color=$YELLOW
    else
        color=$GREEN
    fi

    echo -e "  Uptime:    $(uptime -p)"
    echo -e "  CPU Cores: ${cpu_count}"
    echo -e "  Load Avg:  ${color}${load1}${NC} (1m)  ${load5} (5m)  ${load15} (15m)"
}

check_cpu() {
    print_header "CPU Usage"
    local cpu_usage color

    # Parse idle % from top; the 'id' label is locale-independent and
    # position-independent when extracted this way.
    cpu_usage=$(top -bn1 | grep -E "^(%Cpu|Cpu)" | \
        awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /id/) {gsub(/[^0-9.]/,"",$i); printf "%d", 100-$i}}')

    # Fallback: calculate from /proc/stat if top parsing failed
    if [ -z "$cpu_usage" ]; then
        local user nice system idle iowait irq softirq steal total
        read -r _ user nice system idle iowait irq softirq steal _ < <(grep '^cpu ' /proc/stat)
        total=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
        cpu_usage=$(( total > 0 ? (total - idle) * 100 / total : 0 ))
    fi

    if [ "$cpu_usage" -gt 90 ]; then
        color=$RED
    elif [ "$cpu_usage" -gt 75 ]; then
        color=$YELLOW
    else
        color=$GREEN
    fi

    echo -e "  CPU Usage: ${color}${cpu_usage}%${NC}"
    echo -e "\n  ${YELLOW}Top 5 CPU consuming processes:${NC}"
    ps aux --sort=-%cpu | awk 'NR==1 {printf "  %s\n",$0} NR>1 && NR<=6 {printf "  %s\n",$0}'
}

check_critical_services() {
    print_header "Critical Services Status"

    check_service "nginx"

    # Prefer MariaDB service name if present, fall back to mysql
    if systemctl list-units --type=service --all 2>/dev/null | grep -q "mariadb.service"; then
        check_service "mariadb"
    else
        check_service "mysql"
    fi

    # Detect the active PHP-FPM version dynamically
    local php_fpm_svc
    php_fpm_svc=$(systemctl list-units --type=service --state=active 2>/dev/null | \
        grep -oP 'php\d+\.\d+-fpm' | head -1)
    if [ -n "$php_fpm_svc" ]; then
        check_service "${php_fpm_svc}"
    else
        # Fall back to probing common versions
        local v
        for v in 8.3 8.2 8.1 8.0 7.4; do
            if systemctl list-units --type=service --all 2>/dev/null | \
                    grep -q "php${v}-fpm.service"; then
                check_service "php${v}-fpm"
                break
            fi
        done
    fi

    # Cron (may be 'cron' on Debian/Ubuntu or 'crond' on RHEL-based)
    local cron_svc
    cron_svc=$(systemctl list-units --type=service --all 2>/dev/null | \
        grep -oE 'cron(d)?\.service' | head -1 | sed 's/\.service//')
    [ -n "$cron_svc" ] && check_service "$cron_svc"

    # Supervisor (yiimp workers)
    if systemctl list-units --type=service --all 2>/dev/null | \
            grep -q "supervisor.service"; then
        check_service "supervisor"
    fi

    # Fail2ban
    if systemctl list-units --type=service --all 2>/dev/null | \
            grep -q "fail2ban.service"; then
        check_service "fail2ban"
    fi
}

check_stratum() {
    print_header "Stratum Screen Sessions"
    local session_count=0
    if screen -ls 2>/dev/null | grep -qE "^\s+[0-9]"; then
        while IFS= read -r line; do
            echo -e "  ${GREEN}[✓]${NC} ${line}"
            (( session_count++ ))
        done < <(screen -ls 2>/dev/null | grep -E "^\s+[0-9]")
        echo -e "\n  ${GREEN}Total sessions: ${session_count}${NC}"
    else
        echo -e "  ${YELLOW}[!] No active screen sessions found${NC}"
    fi
}

check_database() {
    print_header "Database Status"

    # Use credentials from .yiimp.conf when available
    local mysql_auth=""
    if [ -n "${DB_USER:-}" ] && [ -n "${DB_PASS:-}" ]; then
        mysql_auth="-u${DB_USER} -p${DB_PASS}"
    fi

    if mysqladmin $mysql_auth ping >/dev/null 2>&1; then
        echo -e "  ${GREEN}[✓] MySQL/MariaDB is responding${NC}"
        echo -e "\n  Database Sizes:"
        mariadb $mysql_auth -N -e \
            "SELECT table_schema,
                    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
             FROM information_schema.tables
             GROUP BY table_schema
             ORDER BY 2 DESC;" 2>/dev/null | \
        while read -r db size; do
            [ -z "$db" ] && continue
            if (( $(echo "$size > 1000" | bc -l) )); then
                echo -e "    ${RED}${db}: ${size} MB${NC}"
            elif (( $(echo "$size > 500" | bc -l) )); then
                echo -e "    ${YELLOW}${db}: ${size} MB${NC}"
            else
                echo -e "    ${GREEN}${db}: ${size} MB${NC}"
            fi
        done
    else
        echo -e "  ${RED}[✗] MySQL/MariaDB is not responding${NC}"
    fi
}

check_ssl() {
    print_header "SSL Certificate Status"

    # Search candidate paths in priority order
    local CERT_FILE=""
    local candidates=(
        "$STORAGE_ROOT/ssl/ssl_certificate.pem"
        "$STORAGE_ROOT/ssl/fullchain.pem"
        "/etc/letsencrypt/live/${DomainName}/fullchain.pem"
        "/etc/letsencrypt/live/${DomainName}/cert.pem"
        "/etc/letsencrypt/live/${DomainName}/ssl_certificate.pem"
    )

    for f in "${candidates[@]}"; do
        if [ -f "$f" ]; then
            CERT_FILE="$f"
            break
        fi
    done

    if [ -z "$CERT_FILE" ]; then
        echo -e "  ${RED}[✗] SSL Certificate not found. Checked paths:${NC}"
        for f in "${candidates[@]}"; do
            echo -e "       $f"
        done
        return
    fi

    echo -e "  Certificate: ${CERT_FILE}"

    local expiry expiry_date current_date days_left
    expiry=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
    expiry_date=$(date -d "$expiry" +%s)
    current_date=$(date +%s)
    days_left=$(( (expiry_date - current_date) / 86400 ))

    if [ "$days_left" -lt 0 ]; then
        echo -e "  ${RED}[✗] SSL Certificate EXPIRED $(( -days_left )) days ago — renew immediately!${NC}"
    elif [ "$days_left" -lt 7 ]; then
        echo -e "  ${RED}[!] SSL Certificate expires in ${days_left} days — renew immediately!${NC}"
    elif [ "$days_left" -lt 30 ]; then
        echo -e "  ${YELLOW}[!] SSL Certificate expires in ${days_left} days${NC}"
    else
        echo -e "  ${GREEN}[✓] SSL Certificate valid for ${days_left} days${NC}"
    fi
}

main() {
    echo -e "${YELLOW}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║         SQSYIIMP System Health Check             ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
    echo -e "  ${MAGENTA}Version:  ${NC}${VERSION}"
    echo -e "  ${MAGENTA}Hostname: ${NC}$(hostname)"
    echo -e "  ${MAGENTA}Date:     ${NC}$(date '+%Y-%m-%d %H:%M:%S %Z')"

    check_disk_space
    check_swap
    check_memory
    check_load
    check_cpu
    check_critical_services
    check_stratum
    check_database
    check_ssl

    print_header "Health Check Complete"
    echo -e "  ${YELLOW}Please review any warnings or errors above.${NC}\n"
}

main
