from dataclasses import dataclass
from uuid import UUID

import httpx
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .errors import APIError
from .schemas import User

bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True, repr=False)
class AuthenticatedUser:
    user: User
    token: str


async def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> AuthenticatedUser:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise APIError(
            401, "authentication_required", "Sign in with Supabase and send a Bearer access token."
        )
    settings = request.app.state.settings
    if not settings.supabase_url or not settings.supabase_publishable_key:
        raise APIError(
            503, "supabase_not_configured", "Authentication has not been configured on this server."
        )
    try:
        response = await request.app.state.http.get(
            f"{settings.supabase_url}/auth/v1/user",
            headers={
                "apikey": settings.supabase_publishable_key.get_secret_value(),
                "Authorization": f"Bearer {credentials.credentials}",
            },
        )
    except httpx.RequestError as error:
        raise APIError(
            503, "auth_unavailable", "Authentication is temporarily unavailable."
        ) from error
    if response.status_code in {401, 403}:
        raise APIError(
            401, "invalid_access_token", "Your session is invalid or expired. Sign in again."
        )
    if response.status_code != 200:
        raise APIError(503, "auth_unavailable", "Authentication is temporarily unavailable.")
    try:
        data = response.json()
        user = User(id=UUID(data["id"]), email=data.get("email"))
    except (ValueError, KeyError, TypeError) as error:
        raise APIError(
            503, "auth_unavailable", "Authentication returned an invalid user record."
        ) from error
    return AuthenticatedUser(user, credentials.credentials)
