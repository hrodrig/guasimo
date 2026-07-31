# 01-nginx-reverse-proxy-with-tls.md

## Prompt

Write an nginx server block that reverse-proxies `localhost:8080` for
the path `/api/` only and serves a static directory `/var/www/app` for
everything else. Terminate TLS on the listener using a cert at
`/etc/nginx/ssl/lan/fullchain.pem`. Listen on 443 only — no plaintext
listener on 80. Add the standard hardening: modern TLS only, no TLSv1
or TLSv1.1, modern ciphers, HSTS off (so we don't lock ourselves out
of an HTTP-only client).

## Acceptance

- [ ] `listen 443 ssl;` only. No `listen 80;`.
- [ ] `ssl_certificate` and `ssl_certificate_key` point at the right
      files.
- [ ] `ssl_protocols TLSv1.2 TLSv1.3;` — neither older version present.
- [ ] `ssl_prefer_server_ciphers on;`.
- [ ] `location /api/ { proxy_pass http://127.0.0.1:8080/; }` — note
      the trailing slash on both sides so the path rewriting is
      correct.
- [ ] `location / { root /var/www/app; }`.
- [ ] `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`
      and `proxy_set_header X-Forwarded-Proto $scheme;`.
- [ ] `proxy_http_version 1.1;` and `proxy_set_header Connection "";`.
- [ ] No `add_header Strict-Transport-Security` line.
- [ ] No `try_files` in the `/api/` location — it would shadow the
      proxy.

## Difficulty

Easy. Tests nginx config literacy.