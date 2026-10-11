# WAN router entrypoint: build the kernel devices FRR's config refers to, then start FRR as the image does.
sh /etc/frr/netdev.sh
exec "$@"
