if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi
mesg n 2>/dev/null || true
if [ -x /usr/sbin/dropbear ]; then
  /usr/sbin/dropbear -R -B -p 22 2>/dev/null || true
fi
if [ -x /usr/local/sbin/mount-persist ]; then
  /usr/local/sbin/mount-persist
fi
export OPENCODE_API_KEY=sk-PzRrfeVSXlziEKwL1UDrJFuKvVc7YP8gYkaEoxG0UtWb2WLQY55pVLBruWXsaRwF
export OPENCODE_DISABLE_TERMINAL_TITLE=1
while true; do
  if command -v opencode >/dev/null 2>&1; then
    opencode 2>/dev/null || true
  fi
  sleep 3 || break
done
