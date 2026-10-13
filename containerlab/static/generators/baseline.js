// Internet users: a constant request rate against the web app's public VIP.
import http from 'k6/http';

const target = __ENV.TARGET || 'http://192.0.2.10';

export const options = {
  // A new connection per request gives every request its own source port, so the ECMP hash on the
  // WAN routers (layer 4) can spread them over all paths instead of pinning one keep-alive flow.
  noConnectionReuse: true,
  scenarios: {
    users: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RPS || 5),
      timeUnit: '1s',
      duration: '8760h',
      preAllocatedVUs: 20,
    },
  },
};

export default function () {
  http.get(`${target}/`, { timeout: '5s' });
  http.get(`${target}/api/products`, { timeout: '5s' });
}
