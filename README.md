On an anisca vision AVI-1-1, run this command 

´curl -H "Cache-Control: no-cache" -H "Pragma: no-cache" -fsSL "https://install.anisca.io" | sh`

- Audio capture must be manually enabled via env var and by /etc/init.d/audio-capture enable
curl -fsSL "https://install.anisca.io?$(date +%s)" | sh

rm -rf /tmp/luci-*
/etc/init.d/uhttpd restart
