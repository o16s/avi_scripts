On an anisca vision AVI-1-1, run this command 

´curl -H "Cache-Control: no-cache" -H "Pragma: no-cache" -fsSL "https://install.anisca.io" | sh`

- Audio capture must be manually enabled via env var and by /etc/init.d/audio-capture enable
curl -fsSL "https://install.anisca.io?$(date +%s)" | sh


- luci cache:
rm -rf /tmp/luci-*
/etc/init.d/uhttpd restart
logout from luci + log back in
- services page will not appear if there are multiple registrations that conflict! (2 similare lua files)