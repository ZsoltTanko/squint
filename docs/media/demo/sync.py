"""Nightly job: sync active users from the accounts service into the mailing list.

Demo content for docs/media/RECORDING.md. Running it prints a real traceback
for the `ask-error.gif` clip.
"""

import json


class Response:
    def __init__(self, status, body=""):
        self.status = status
        self.body = body


class AccountsSession:
    """Stand-in for the HTTP client. The accounts service is down tonight."""

    def get(self, path):
        return Response(status=503)


def fetch_users(session):
    resp = session.get("/v2/users?active=true")
    if resp.status != 200:
        print(f"warning: accounts service returned {resp.status}")
        return None
    return json.loads(resp.body)


def main():
    session = AccountsSession()
    for user in fetch_users(session)["results"]:
        print(f"syncing {user['email']}")


if __name__ == "__main__":
    main()
