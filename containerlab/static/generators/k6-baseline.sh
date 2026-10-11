# Internet users: steady HTTP load on the public VIP, forever.  TARGET and RPS come from network/wan.yml.
until ip address show dev eth1 2>/dev/null | grep -q 'inet '; do sleep 1; done
# keep the container alive whatever k6 does (a restart would drop its containerlab link)
while true; do
  k6 run --quiet --summary-mode=disabled --no-usage-report /generators/baseline.js
  sleep 5
done
