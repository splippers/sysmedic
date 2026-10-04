## Installed toolkit (this is an installed system: `apt install` works when online)

- **Joining Wi-Fi**: the engineer runs `wifi` (rescue menu option 2): NetworkManager's on-screen picker. It is full-screen, so don't run it yourself; to check the result use `nmcli device` and `nmcli dev wifi list`.
- **Network**: ping, arping, tracepath, traceroute, mtr (use `mtr -rwc 10`), dig, nslookup, whois, ip, ss, ethtool, iw, nmcli, wavemon, iperf3, speedtest-cli, curl, tcpdump/tshark (always with `-c N`), smbclient, cifs-utils, nfs-common (NFSv3 needs `systemctl start rpcbind`), snmp, lldpcli (`systemctl start lldpd` first), ndisc6, ipcalc, sipcalc, minicom/picocom, ipmitool. Only probe other machines (nmap, arp-scan, nbtscan) when the engineer asks, on networks they're allowed to test.
- **Disks and data recovery**: smartctl, nvme, hdparm, ddrescue, safecopy, testdisk, photorec, foremost, scalpel, ext4magic, extundelete, partclone, fsarchiver, f3 (fake-capacity USB check), nwipe (secure erase: destructive, engineer only), lsscsi, sg3-utils
- **Filesystems**: ntfs-3g, exfatprogs, dosfstools, btrfs-progs, xfsprogs, f2fs-tools, hfsprogs, fsapfsmount (APFS read-only), apfsck, mdadm, lvm2, cryptsetup, dislocker
- **Hardware**: lshw, hwinfo, inxi, dmidecode, sensors, decode-dimms, edid-decode, stress-ng, memtester, fwupdmgr (firmware updates), powertop, mokutil
- **Windows**: sysmedic-win (incl. evtx, registry, cbs, checkup), cabextract, chntpw, hivexget, wimlib-imagex (WIM/ESD images), evtxexport, clamscan
- **Security**: clamscan, yara, chkrootkit, rkhunter (for Linux patients: point them at the mounted root with `-r`)
- **Everyday**: htop, btop, ncdu, mc, rsync, rclone, sshfs, pv, jq, 7z, iotop-c, sar, lsof, strace, tmux
- **Advanced toolkit**: `/opt/sysmedic/menu.sh` (stress/burn-in tests, OS image capture/restore, macOS scan/mount/repair, extra Windows repairs)

---
