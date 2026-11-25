import base64, hashlib, hmac, json, os, re, secrets, time

HOME = os.path.expanduser("~")
ROOT = os.path.join(HOME, "bumper")
ENV = os.path.join(ROOT, ".env")
SITE = os.path.join(ROOT, "site", "index.html")
DOMAIN = "bumper.fat.plus"
PORT = "10443"


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def make_token(secret):
    now = int(time.time())
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"role": "anon", "iss": "bumper", "iat": now, "exp": now + 3650 * 86400}
    si = b64(json.dumps(header, separators=(",", ":")).encode()) + "." + \
         b64(json.dumps(payload, separators=(",", ":")).encode())
    sig = hmac.new(secret.encode(), si.encode(), hashlib.sha256).digest()
    return si + "." + b64(sig)


vals = {}
if os.path.exists(ENV):
    for line in open(ENV, encoding="utf-8"):
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            vals[k] = v
else:
    vals = {
        "DB_PASSWORD": secrets.token_urlsafe(24),
        "AUTH_PASSWORD": secrets.token_urlsafe(24),
        "JWT_SECRET": secrets.token_urlsafe(48),
    }
    vals["ANON_KEY"] = make_token(vals["JWT_SECRET"])
    with open(ENV, "w", encoding="utf-8") as f:
        for k in ("DB_PASSWORD", "AUTH_PASSWORD", "JWT_SECRET", "ANON_KEY"):
            f.write("%s=%s\n" % (k, vals[k]))
    os.chmod(ENV, 0o600)

if "ANON_KEY" not in vals:
    vals["ANON_KEY"] = make_token(vals["JWT_SECRET"])
    with open(ENV, "a", encoding="utf-8") as f:
        f.write("ANON_KEY=%s\n" % vals["ANON_KEY"])

src = open(SITE, encoding="utf-8").read()
orig = src
src = re.sub(r"url:\s*'https?://[^']*'", "url:     'https://%s:%s'" % (DOMAIN, PORT), src, count=1)
src = re.sub(r"anonKey:\s*'[^']*'", "anonKey: '%s'" % vals["ANON_KEY"], src, count=1)
if src != orig:
    open(SITE, "w", encoding="utf-8").write(src)

check_url = re.search(r"url:\s*'([^']*)'", src).group(1)
check_key = re.search(r"anonKey:\s*'([^']*)'", src).group(1)
print("env=%s mode=%s" % (ENV, oct(os.stat(ENV).st_mode)[-3:]))
print("url=%s" % check_url)
print("key_prefix=%s len=%d" % (check_key[:12], len(check_key)))
print("key_is_jwt=%s" % check_key.startswith("eyJ"))
