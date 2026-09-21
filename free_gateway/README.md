# Free proxy gateway

This service lets a public APL build offer operator-funded locations without shipping supplier credentials to the APK.

## Trust boundary

The client calls the API for public locations and a short-lived session. The returned credential authenticates only to the Arvectum gateway. The gateway then opens the supplier proxy connection with credentials loaded from its own environment.

Supplier host/login/password must never be placed in Android resources, BuildConfig, GitHub Actions variables used to build the APK, or committed files.

## Where to enter the real proxies

On the gateway server, create a root/service-user-readable environment file outside the repository, for example /etc/arvectum-proxy-gateway/gateway.env.

Put APL_GATEWAY_TOKEN_SECRET and APL_FREE_PROXIES_JSON there. APL_FREE_PROXIES_JSON is an array; add one object per free location. tls=false means a normal HTTP CONNECT upstream. Set tls=true only when the supplier explicitly provides an HTTPS proxy endpoint.

Recommended Linux permissions:

    sudo chown root:root /etc/arvectum-proxy-gateway/gateway.env
    sudo chmod 600 /etc/arvectum-proxy-gateway/gateway.env

Generate the signing secret with a password generator or: openssl rand -hex 32

## Public endpoints

GET /v1/free/locations returns only id, display label and country code.

POST /v1/free/session with {"location_id":"de-free"} returns the Arvectum gateway host/port plus a short-lived Basic-auth username/password. It never returns the supplier endpoint or supplier credentials.

The proxy listener accepts authenticated HTTP CONNECT. A stolen session credential expires quickly and is bound to one location.

## Deployment note

Terminate public TLS for the API at a reverse proxy/load balancer. The CONNECT listener itself is an HTTP proxy port; production deployment should firewall/rate-limit it and expose only the intended port. This MVP protects supplier credentials, but it is not an anti-abuse system: add per-install quotas/rate limiting before large public rollout.
