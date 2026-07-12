if [ -f /persistent/var/lib/systemd/credential.secret ] && \
   [ "$(@coreutils@/bin/stat -c %s /persistent/var/lib/systemd/credential.secret)" = "4096" ]; then
  @coreutils@/bin/rm -f /persistent/var/lib/systemd/credential.secret
fi
