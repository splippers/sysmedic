#!/bin/bash
# Albatross Fleet Metrics — called by snmpd extend directive
# Output is captured per OID under NET-SNMP-EXTEND-MIB

# Docker
if command -v docker &>/dev/null; then
  echo "docker-running:$(docker ps -q 2>/dev/null | wc -l)"
  echo "docker-all:$(docker ps -aq 2>/dev/null | wc -l)"
  echo "docker-images:$(docker images -q 2>/dev/null | wc -l)"
else
  echo "docker-running:0"
  echo "docker-all:0"
  echo "docker-images:0"
fi

# Ollama
if command -v ollama &>/dev/null; then
  echo "ollama-models:$(ollama list 2>/dev/null | tail -n +2 | wc -l)"
  # Check if ollama service is responsive
  if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    echo "ollama-status:up"
  else
    echo "ollama-status:down"
  fi
else
  echo "ollama-models:0"
  echo "ollama-status:none"
fi

# Memory details from /proc/meminfo
if [ -r /proc/meminfo ]; then
  eval $(awk '/^MemTotal:/{t=$2} /^MemFree:/{f=$2} /^MemAvailable:/{a=$2} /^Cached:/{c=$2} /^Buffers:/{b=$2} /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2} END{printf "MT=%d MF=%d MA=%d MC=%d MB=%d ST=%d SF=%d", t,f,a,c,b,st,sf}' /proc/meminfo)
  echo "mem-total-mb:$((MT/1024))"
  echo "mem-free-mb:$((MF/1024))"
  echo "mem-avail-mb:$((MA/1024))"
  echo "mem-cached-mb:$((MC/1024))"
  echo "mem-buffers-mb:$((MB/1024))"
  echo "swap-total-mb:$((ST/1024))"
  echo "swap-free-mb:$((SF/1024))"
  echo "swap-used-mb:$(( (ST-SF) /1024 ))"
fi

# System limits
if [ -r /proc/sys/fs/file-nr ]; then
  echo "open-fds:$(awk '{print $1}' /proc/sys/fs/file-nr)"
fi

# Network connections
echo "tcp-conn:$(ss -tH state established 2>/dev/null | wc -l)"
echo "udp-conn:$(ss -uH 2>/dev/null | wc -l)"
echo "listen-ports:$(ss -tlnH 2>/dev/null | wc -l)"

# Process info
echo "zombie-procs:$(ps aux 2>/dev/null | awk '/[Zz]/{count++} END{print count+0}')"
echo "total-procs:$(ps aux 2>/dev/null | wc -l)"
echo "total-users:$(who 2>/dev/null | awk '{print $1}' | sort -u | wc -l)"

# Top CPU consumer
echo "top-cpu:$(ps aux --sort=-%cpu 2>/dev/null | awk 'NR==2{printf "%s %.1f%%", $11, $3}')"
# Top MEM consumer
echo "top-mem:$(ps aux --sort=-%mem 2>/dev/null | awk 'NR==2{printf "%s %.1f%%", $11, $4}')"

# Interface bandwidth (since boot, from /proc/net/dev)
if [ -r /proc/net/dev ]; then
  awk 'NR>2 {rx+=$2; tx+=$10} END{printf "net-rx-bytes:%d\nnet-tx-bytes:%d\n", rx, tx}' /proc/net/dev
fi

# GlusterFS
if command -v gluster &>/dev/null; then
  gluster volume status 2>/dev/null | head -1 && echo "gluster:present" || echo "gluster:inactive"
else
  echo "gluster:none"
fi

# Keepalived
if command -v keepalived &>/dev/null; then
  echo "keepalived:$(pidof keepalived 2>/dev/null | wc -w)"
else
  echo "keepalived:0"
fi

# Disk I/O from /proc/diskstats (aggregate)
if [ -r /proc/diskstats ]; then
  awk '$3 ~ /^(sd|nvme|vd|hd)[a-z]/ && $3 !~ /[0-9]$/ {reads+=$4; writes+=$8; read_sectors+=$6; write_sectors+=$10} END{printf "disk-reads:%d\ndisk-writes:%d\ndisk-read-sectors:%d\ndisk-write-sectors:%d\n", reads, writes, read_sectors, write_sectors}' /proc/diskstats
fi

# Running services (key systemd units)
for unit in snmpd sshd cron docker ollama nginx keepalived glusterd; do
  case "$(systemctl is-active "$unit" 2>/dev/null)" in
    active) echo "svc-$unit:active" ;;
    inactive) echo "svc-$unit:inactive" ;;
    failed) echo "svc-$unit:failed" ;;
    *) echo "svc-$unit:unknown" ;;
  esac
done
