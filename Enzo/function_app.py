import azure.functions as func
import json
import logging
import os
import re
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import bcrypt
import jwt
import requests
from azure.cosmos import CosmosClient, exceptions as cosmos_exceptions

app = func.FunctionApp()

# ---------------------------------------------------------------------------
# Configuration (all pulled from local.settings.json locally, or Function App
# Application Settings once deployed — never hardcoded).
# ---------------------------------------------------------------------------
COSMOS_ENDPOINT = os.environ["COSMOS_ENDPOINT"]
COSMOS_KEY = os.environ["COSMOS_KEY"]
JWT_SECRET = os.environ["JWT_SECRET"]
GITHUB_CLIENT_ID = os.environ["GITHUB_CLIENT_ID"]
GITHUB_CLIENT_SECRET = os.environ["GITHUB_CLIENT_SECRET"]
GITHUB_REDIRECT_URI = os.environ.get(
    "GITHUB_REDIRECT_URI", "http://localhost:7071/api/auth/github/callback"
)
FRONTEND_URL = os.environ.get("FRONTEND_URL", "http://127.0.0.1:5500")

JWT_EXPIRY_HOURS = 12
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
}

cosmos_client = CosmosClient(COSMOS_ENDPOINT, COSMOS_KEY)
database = cosmos_client.get_database_client("AuthDB")
users_container = database.get_container_client("Users")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def json_response(body: dict, status_code: int = 200) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(body),
        status_code=status_code,
        mimetype="application/json",
        headers=CORS_HEADERS,
    )


def hash_password(password: str) -> str:
    # bcrypt generates and embeds its own salt automatically.
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def issue_jwt(user: dict) -> str:
    payload = {
        "sub": user["email"],
        "name": user.get("name", ""),
        "provider": user.get("auth_provider", "local"),
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(hours=JWT_EXPIRY_HOURS),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def decode_jwt(token: str):
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError as e:
        logging.warning(f"JWT decode failed: {e}")
        return None


def get_user_by_email(email: str):
    # id and partition key are both the email, so this is a fast point read
    # rather than a cross-partition query.
    try:
        return users_container.read_item(item=email, partition_key=email)
    except cosmos_exceptions.CosmosResourceNotFoundError:
        return None


def upsert_user(user: dict) -> None:
    users_container.upsert_item(user)


# ---------------------------------------------------------------------------
# Email / Password registration
# ---------------------------------------------------------------------------
@app.route(route="register", methods=["POST", "OPTIONS"], auth_level=func.AuthLevel.ANONYMOUS)
def register(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return func.HttpResponse(status_code=204, headers=CORS_HEADERS)

    try:
        body = req.get_json()
    except ValueError:
        return json_response({"error": "Invalid JSON body"}, 400)

    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""
    name = (body.get("name") or "").strip()

    if not EMAIL_RE.match(email):
        return json_response({"error": "Enter a valid email address"}, 400)
    if len(password) < 8:
        return json_response({"error": "Password must be at least 8 characters"}, 400)
    if not name:
        return json_response({"error": "Name is required"}, 400)

    if get_user_by_email(email):
        return json_response({"error": "An account with this email already exists"}, 409)

    user = {
        "id": email,
        "email": email,
        "name": name,
        "password_hash": hash_password(password),  # only the hash is ever stored
        "auth_provider": "local",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    upsert_user(user)

    token = issue_jwt(user)
    return json_response({"token": token, "name": user["name"], "email": user["email"]}, 201)


# ---------------------------------------------------------------------------
# Email / Password login
# ---------------------------------------------------------------------------
@app.route(route="login", methods=["POST", "OPTIONS"], auth_level=func.AuthLevel.ANONYMOUS)
def login(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return func.HttpResponse(status_code=204, headers=CORS_HEADERS)

    try:
        body = req.get_json()
    except ValueError:
        return json_response({"error": "Invalid JSON body"}, 400)

    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""

    user = get_user_by_email(email)
    if not user or "password_hash" not in user:
        # Same message whether the account doesn't exist or the password is
        # wrong — don't leak which one it was.
        return json_response({"error": "Invalid email or password"}, 401)

    if not verify_password(password, user["password_hash"]):
        return json_response({"error": "Invalid email or password"}, 401)

    token = issue_jwt(user)
    return json_response({"token": token, "name": user["name"], "email": user["email"]}, 200)


# ---------------------------------------------------------------------------
# Logout — JWTs are stateless, so this just tells the frontend the token is
# no longer valid; the actual deletion happens client-side.
# ---------------------------------------------------------------------------
@app.route(route="logout", methods=["POST", "OPTIONS"], auth_level=func.AuthLevel.ANONYMOUS)
def logout(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return func.HttpResponse(status_code=204, headers=CORS_HEADERS)
    return json_response({"message": "Logged out"}, 200)


# ---------------------------------------------------------------------------
# Who am I — the dashboard calls this with the stored token to get the name
# to display top-right, and to confirm the session is still valid.
# ---------------------------------------------------------------------------
@app.route(route="me", methods=["GET", "OPTIONS"], auth_level=func.AuthLevel.ANONYMOUS)
def me(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return func.HttpResponse(status_code=204, headers=CORS_HEADERS)

    auth_header = req.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return json_response({"error": "Missing bearer token"}, 401)

    payload = decode_jwt(auth_header[len("Bearer "):].strip())
    if not payload:
        return json_response({"error": "Invalid or expired token"}, 401)

    return json_response({"email": payload["sub"], "name": payload["name"]}, 200)


# ---------------------------------------------------------------------------
# GitHub OAuth — step 1: send the browser to GitHub to authorize
# ---------------------------------------------------------------------------
@app.route(route="auth/github/login", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def github_login(req: func.HttpRequest) -> func.HttpResponse:
    state = secrets.token_urlsafe(16)
    params = {
        "client_id": GITHUB_CLIENT_ID,
        "redirect_uri": GITHUB_REDIRECT_URI,
        "scope": "read:user user:email",
        "state": state,
    }
    github_url = f"https://github.com/login/oauth/authorize?{urlencode(params)}"
    return func.HttpResponse(status_code=302, headers={"Location": github_url})


# ---------------------------------------------------------------------------
# GitHub OAuth — step 2: GitHub redirects back here with a code
# ---------------------------------------------------------------------------
@app.route(route="auth/github/callback", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def github_callback(req: func.HttpRequest) -> func.HttpResponse:
    code = req.params.get("code")
    if not code:
        return json_response({"error": "Missing authorization code"}, 400)

    token_resp = requests.post(
        "https://github.com/login/oauth/access_token",
        headers={"Accept": "application/json"},
        data={
            "client_id": GITHUB_CLIENT_ID,
            "client_secret": GITHUB_CLIENT_SECRET,
            "code": code,
            "redirect_uri": GITHUB_REDIRECT_URI,
        },
        timeout=10,
    )
    token_data = token_resp.json()
    access_token = token_data.get("access_token")
    if not access_token:
        logging.error(f"GitHub token exchange failed: {token_data}")
        return json_response({"error": "GitHub authorization failed"}, 400)

    gh_headers = {"Authorization": f"Bearer {access_token}"}
    profile = requests.get("https://api.github.com/user", headers=gh_headers, timeout=10).json()

    email = profile.get("email")
    if not email:
        # Public email can be null even with the user:email scope — fall back
        # to the verified primary from /user/emails.
        emails = requests.get(
            "https://api.github.com/user/emails", headers=gh_headers, timeout=10
        ).json()
        primary = next((e["email"] for e in emails if e.get("primary") and e.get("verified")), None)
        email = primary or f"{profile['login']}@users.noreply.github.com"

    email = email.strip().lower()
    name = profile.get("name") or profile["login"]

    user = get_user_by_email(email)
    if not user:
        user = {
            "id": email,
            "email": email,
            "name": name,
            "auth_provider": "github",
            "github_id": profile["id"],
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        upsert_user(user)

    token = issue_jwt(user)
    # Token goes in the URL fragment, not a query string — fragments aren't
    # sent to the server or logged, only readable by JS on the page.
    redirect_url = f"{FRONTEND_URL}/#token={token}"
    return func.HttpResponse(status_code=302, headers={"Location": redirect_url})
